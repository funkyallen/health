from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from backend.models.alarm_model import AlarmQueueItem, AlarmRecord, MobilePushRecord
from backend.models.health_model import HealthSample


logger = logging.getLogger(__name__)


class AlarmService:
    """Evaluates incoming samples and stores active alarms."""

    def __init__(
        self,
        detector: object,
        queue: object,
        notification_service: object,
        *,
        sos_dedupe_window_seconds: int = 15,
    ) -> None:
        self._detector = detector
        self._queue = queue
        self._notification_service = notification_service
        self._alarms: list[AlarmRecord] = []
        self._sos_dedupe_window = timedelta(seconds=max(1, sos_dedupe_window_seconds))
        # Post-acknowledgment cooldown: after a user dismisses an SOS popup,
        # the bracelet may still broadcast SOS packets for 30+ seconds.
        # This dict tracks {device_mac: ack_timestamp} so we can suppress
        # new SOS alerts during the cooldown period.
        self._sos_ack_cooldowns: dict[str, datetime] = {}
        self._sos_ack_cooldown_duration = timedelta(
            seconds=30, # 30 seconds covers the broadcast window while being test-friendly
        )

    def evaluate(self, sample: HealthSample) -> list[AlarmRecord]:
        alarms = self._detector.evaluate(sample)
        return self.evaluate_alarm_records(alarms)

    def evaluate_alarm_records(self, alarms: list[AlarmRecord]) -> list[AlarmRecord]:
        normalized: list[AlarmRecord] = []
        if alarms:
            for alarm in alarms:
                upserted = self._upsert_alarm(alarm)
                if upserted is not None:
                    normalized.append(upserted)
        self._alarms.sort(key=lambda item: (item.alarm_level.value, item.created_at), reverse=False)
        return normalized

    def list_alarms(self, device_mac: str | None = None, active_only: bool = False) -> list[AlarmRecord]:
        alarms = self._alarms
        if device_mac:
            alarms = [alarm for alarm in alarms if alarm.device_mac == device_mac.upper()]
        if active_only:
            alarms = [alarm for alarm in alarms if not alarm.acknowledged]
        return alarms

    def queue_items(self, active_only: bool = True) -> list[AlarmQueueItem]:
        return self._queue.items(active_only=active_only)

    def queue_snapshot(self) -> dict[str, object]:
        return self._queue.snapshot()

    def list_mobile_pushes(self, limit: int = 50) -> list[MobilePushRecord]:
        return self._notification_service.list_mobile_pushes(limit=limit)

    def acknowledge(self, alarm_id: str) -> AlarmRecord | None:
        for index, alarm in enumerate(self._alarms):
            if alarm.id == alarm_id:
                updated = alarm.model_copy(update={"acknowledged": True})
                self._alarms[index] = updated
                self._queue.remove(alarm_id)
                # Record SOS acknowledgment so subsequent broadcasts from
                # the same physical button press are silently suppressed.
                if alarm.alarm_type.value == "sos":
                    mac = alarm.device_mac.upper()
                    self._sos_ack_cooldowns[mac] = datetime.now(timezone.utc)
                    logger.info(
                        "SOS acknowledged for %s — cooldown active for %ds.",
                        mac,
                        self._sos_ack_cooldown_duration.total_seconds(),
                    )
                return updated
        return None

    def _upsert_alarm(self, alarm: AlarmRecord) -> AlarmRecord | None:
        # Check post-acknowledgment cooldown first: if the user just dismissed
        # an SOS for this device, suppress subsequent SOS packets silently.
        if alarm.alarm_type.value == "sos" and self._is_in_sos_ack_cooldown(alarm.device_mac):
            return None

        existing_index = self._find_active_sos_index(alarm)
        if existing_index is not None:
            self._collapse_active_sos_duplicates(
                device_mac=alarm.device_mac,
                keep_alarm_id=self._alarms[existing_index].id,
            )
            # Repeated SOS packets from the same active event should not emit
            # another queue item or trigger another popup on clients.
            return None

        self._alarms.append(alarm)
        self._queue.enqueue(alarm)
        self._notification_service.dispatch_mobile_push(alarm)
        return alarm

    def _is_in_sos_ack_cooldown(self, device_mac: str) -> bool:
        """Return True if the device is within the post-acknowledgment cooldown."""
        mac = device_mac.upper()
        ack_at = self._sos_ack_cooldowns.get(mac)
        if ack_at is None:
            return False
        elapsed = datetime.now(timezone.utc) - ack_at
        if elapsed > self._sos_ack_cooldown_duration:
            # Cooldown expired — clear it so future SOS events are not affected.
            del self._sos_ack_cooldowns[mac]
            return False
        logger.debug(
            "SOS suppressed for %s — within post-ack cooldown (%ds/%ds elapsed).",
            mac,
            elapsed.total_seconds(),
            self._sos_ack_cooldown_duration.total_seconds(),
        )
        return True

    def _find_active_sos_index(self, alarm: AlarmRecord) -> int | None:
        if alarm.alarm_type.value != "sos":
            return None
        now = datetime.now(timezone.utc)
        for index in range(len(self._alarms) - 1, -1, -1):
            existing = self._alarms[index]
            if existing.alarm_type.value != "sos":
                continue
            if existing.device_mac != alarm.device_mac or existing.acknowledged:
                continue
            # A single SOS button press causes the bracelet to broadcast packets
            # for ~30 seconds. We group all unacknowledged packets within a 120s
            # window into the same alarm event to prevent multiple popups.
            # If the unacknowledged alarm is older than 120s, it's a stale/abandoned
            # event, so we acknowledge it to clear it, allowing the new SOS to trigger a fresh popup.
            age = now - existing.created_at
            if age.total_seconds() > 120:
                self._alarms[index] = existing.model_copy(update={"acknowledged": True})
                self._queue.remove(existing.id)
                continue
            return index
        return None

    def _collapse_active_sos_duplicates(self, *, device_mac: str, keep_alarm_id: str) -> None:
        for index, existing in enumerate(self._alarms):
            if existing.id == keep_alarm_id:
                continue
            if existing.alarm_type.value != "sos":
                continue
            if existing.device_mac != device_mac or existing.acknowledged:
                continue
            self._alarms[index] = existing.model_copy(update={"acknowledged": True})
            self._queue.remove(existing.id)
