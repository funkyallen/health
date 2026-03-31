<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from "vue";
import type { CommunityDashboardElderItem } from "../api/client";
import { riskLevelToChinese } from "../utils/riskLevel";

const props = defineProps<{
  elders: CommunityDashboardElderItem[];
  selectedElderId: string;
}>();

const emit = defineEmits<{
  select: [elderId: string];
}>();

type CardTone = "sos" | "no-device" | "offline" | "pending" | "risk-high" | "risk-medium" | "risk-low";

const railGridRef = ref<HTMLElement | null>(null);

function elderHasObservedRealtime(elder: CommunityDashboardElderItem) {
  return Boolean(
    elder.latest_timestamp
      || elder.heart_rate != null
      || elder.blood_oxygen != null
      || elder.blood_pressure
      || elder.temperature != null
      || elder.latest_health_score != null,
  );
}

function elderTone(elder: CommunityDashboardElderItem): CardTone {
  if (elder.active_alarm_count > 0) return "sos";
  if (!elder.device_mac || elder.device_status === "no_device") return "no-device";
  if (elder.device_status === "offline") return "offline";
  if (elder.device_status === "pending" && !elderHasObservedRealtime(elder)) return "pending";
  if (elder.risk_level === "high") return "risk-high";
  if (elder.risk_level === "medium") return "risk-medium";
  return "risk-low";
}

function elderLabel(elder: CommunityDashboardElderItem): string {
  if (elder.active_alarm_count > 0) return "告警中";
  if (!elder.device_mac || elder.device_status === "no_device") return "无设备";
  if (elder.device_status === "offline") return "离线";
  if (elder.device_status === "pending" && !elderHasObservedRealtime(elder)) return "待同步";
  return "在线";
}

function elderMeta(elder: CommunityDashboardElderItem): string {
  if (!elder.device_mac || elder.device_status === "no_device") {
    return `${elder.apartment} · 等待移动端绑定手环`;
  }
  if (elder.device_status === "offline") {
    return `${elder.apartment} · 设备暂时离线`;
  }
  if (elder.device_status === "pending" && !elderHasObservedRealtime(elder)) {
    return `${elder.apartment} · 已绑定，等待首包`;
  }
  return `${elder.apartment} · 风险 ${riskLevelToChinese(elder.structured_health?.risk_level ?? elder.risk_level)}`;
}

const noDeviceCount = computed(() => props.elders.filter((elder) => !elder.device_mac || elder.device_status === "no_device").length);
const offlineCount = computed(() => props.elders.filter((elder) => elder.device_status === "offline").length);

async function scrollSelectedIntoView() {
  if (!props.selectedElderId) return;
  await nextTick();
  const target = railGridRef.value?.querySelector<HTMLElement>(`[data-elder-id="${props.selectedElderId}"]`);
  target?.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
}

watch(() => props.selectedElderId, () => {
  void scrollSelectedIntoView();
});

onMounted(() => {
  void scrollSelectedIntoView();
});
</script>

<template>
  <section class="device-rail">
    <div class="device-rail__head">
      <div>
        <p class="section-eyebrow">社区监护总览</p>
        <h2>老人监护对象</h2>
      </div>
      <small>先按老人查看绑定状态；只有已绑定设备的老人，点进去后才会加载实时曲线和监护数据。</small>
    </div>

    <div class="device-rail__meta">
      <span class="summary-badge">老人 {{ elders.length }}</span>
      <span class="summary-badge">无设备 {{ noDeviceCount }}</span>
      <span class="summary-badge">离线 {{ offlineCount }}</span>
    </div>

    <div ref="railGridRef" class="device-rail__grid">
      <button
        v-for="elder in elders"
        :key="elder.elder_id"
        type="button"
        class="device-pill"
        :data-elder-id="elder.elder_id"
        :class="[elderTone(elder), { 'device-pill--active': selectedElderId === elder.elder_id }]"
        @click="emit('select', elder.elder_id)"
      >
        <div class="device-pill__top">
          <strong>{{ elder.elder_name }}</strong>
          <span class="device-pill__state">{{ elderLabel(elder) }}</span>
        </div>
        <small>{{ elder.device_mac ?? "未绑定手环" }}</small>
        <span class="device-pill__meta">{{ elderMeta(elder) }}</span>
      </button>
    </div>
  </section>
</template>

<style scoped>
.device-rail {
  display: grid;
  gap: 12px;
}

.device-rail__head {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  align-items: flex-end;
}

.device-rail__head h2 {
  margin: 0;
  color: var(--text-main);
  font-family: var(--font-display);
}

.device-rail__head small,
.device-pill small,
.device-pill__meta {
  color: var(--text-sub);
  font-size: 0.82rem;
}

.device-rail__meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.device-rail__grid {
  display: grid;
  gap: 10px;
  grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
}

.device-pill {
  display: grid;
  gap: 8px;
  padding: 14px 16px;
  border-radius: 20px;
  border: 1px solid var(--line-medium);
  background: #ffffff;
  text-align: left;
  cursor: pointer;
  transition: transform 160ms ease, border-color 160ms ease, box-shadow 160ms ease;
  box-shadow: 0 2px 8px rgba(15, 23, 42, 0.04);
}

.device-pill:hover,
.device-pill--active {
  transform: translateY(-1px);
  box-shadow: 0 14px 28px rgba(15, 23, 42, 0.08);
}

.device-pill--active {
  border-color: var(--brand);
  background: #eff6ff;
  box-shadow: 0 0 0 1px rgba(37, 99, 235, 0.14), 0 14px 28px rgba(37, 99, 235, 0.12);
}

.device-pill__top {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  align-items: center;
}

.device-pill strong {
  color: var(--text-main);
  font-size: 1rem;
}

.device-pill__state {
  padding: 5px 10px;
  border-radius: 999px;
  font-size: 0.76rem;
  font-weight: 700;
  flex-shrink: 0;
}

.no-device {
  border-color: var(--line-medium);
  background: #f8fafc;
}

.no-device .device-pill__state {
  background: rgba(148, 163, 184, 0.14);
  color: #64748b;
}

.offline {
  border-color: rgba(96, 165, 250, 0.24);
  background: #f0f9ff;
}

.offline .device-pill__state {
  background: rgba(56, 189, 248, 0.14);
  color: #0284c7;
}

.pending {
  border-color: rgba(251, 191, 36, 0.3);
  background: #fffbeb;
}

.pending .device-pill__state {
  background: rgba(251, 191, 36, 0.18);
  color: #b45309;
}

.sos {
  border-color: rgba(239, 68, 68, 0.5);
  background: #fef2f2;
  box-shadow: 0 0 0 1px rgba(239, 68, 68, 0.24), 0 12px 28px rgba(239, 68, 68, 0.16);
}

.sos .device-pill__state {
  background: rgba(239, 68, 68, 0.16);
  color: #b91c1c;
}

.risk-high {
  border-color: rgba(239, 68, 68, 0.3);
  background: #fef2f2;
}

.risk-high .device-pill__state {
  background: rgba(239, 68, 68, 0.16);
  color: #b91c1c;
}

.risk-medium {
  border-color: rgba(245, 158, 11, 0.3);
  background: #fffbeb;
}

.risk-medium .device-pill__state {
  background: rgba(245, 158, 11, 0.18);
  color: #b45309;
}

.risk-low {
  border-color: rgba(16, 185, 129, 0.24);
  background: #f0fdf4;
}

.risk-low .device-pill__state {
  background: rgba(16, 185, 129, 0.14);
  color: #047857;
}

@media (max-width: 760px) {
  .device-rail__head {
    flex-direction: column;
    align-items: flex-start;
  }

  .device-rail__grid {
    grid-template-columns: 1fr;
  }
}
</style>
