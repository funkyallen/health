<script setup lang="ts">
import { computed, toRef } from "vue";

import type { SessionUser } from "../api/client";
import CommunityDeviceInspector from "../components/CommunityDeviceInspector.vue";
import CommunityDeviceRail from "../components/CommunityDeviceRail.vue";
import CommunityRealtimeVitalsPanel from "../components/CommunityRealtimeVitalsPanel.vue";
import PageHeader from "../components/layout/PageHeader.vue";
import { useCommunityWorkspace } from "../composables/useCommunityWorkspace";

const props = defineProps<{
  sessionUser: SessionUser;
}>();

const workspace = useCommunityWorkspace(toRef(props, "sessionUser"));

const syncLabel = computed(() =>
  workspace.lastSyncAt.value
    ? workspace.lastSyncAt.value.toLocaleTimeString("zh-CN", { hour12: false })
    : "尚未同步",
);

const noDeviceCount = computed(() =>
  workspace.topRiskElders.value.filter((item) => !item.device_mac || item.device_status === "no_device").length,
);

const offlineCount = computed(() =>
  workspace.topRiskElders.value.filter((item) => item.device_status === "offline").length,
);

const pageMeta = computed(() => [
  `社区 ${workspace.community.value?.name ?? "未分配"}`,
  `无设备 ${noDeviceCount.value}`,
  `离线 ${offlineCount.value}`,
  `未确认告警 ${workspace.metrics.value?.unacknowledged_alarm_count ?? 0}`,
  `同步 ${syncLabel.value}`,
]);
</script>

<template>
  <section class="page-stack">
    <PageHeader
      eyebrow="Overview"
      title="总览监护"
      description="社区页按老人对象展开监护。无设备时只显示绑定状态；只有完成绑定并点进对应老人后，才会显示实时曲线和详细指标。"
      :meta="pageMeta"
    >
      <template #actions>
        <button type="button" class="ghost-btn" @click="workspace.refreshDashboardData">
          刷新数据
        </button>
      </template>
    </PageHeader>

    <p v-if="workspace.dashboardLoadError.value" class="feedback-banner feedback-error">
      {{ workspace.dashboardLoadError.value }}
    </p>

    <div v-else class="overview-stage">
      <CommunityDeviceRail
        :elders="workspace.topRiskElders.value"
        :selected-elder-id="workspace.selectedElderId.value"
        @select="workspace.setSelectedElderId"
      />

      <CommunityRealtimeVitalsPanel
        :elder="workspace.selectedElder.value"
        :device="workspace.selectedDevice.value"
        :current-sample="workspace.selectedMonitorCurrentSample.value"
        :samples="workspace.selectedMonitorSamples.value"
        :awaiting-realtime="workspace.isAwaitingSelectedRealtime.value"
      />

      <div class="overview-stage__detail-row">
        <CommunityDeviceInspector
          :elder="workspace.selectedElder.value"
          :device="workspace.selectedDevice.value"
        />

        <article class="panel alerts-panel">
          <div class="alerts-panel__head">
            <div>
              <p class="section-eyebrow">Alert Feed</p>
              <h2>最近告警</h2>
            </div>
            <span class="summary-badge">{{ workspace.recentAlerts.value.length }} 条</span>
          </div>

          <div class="alert-list">
            <article
              v-for="item in workspace.recentAlerts.value.slice(0, 6)"
              :key="item.alarm_id"
              class="alert-row"
            >
              <strong>{{ item.elder_name ?? item.device_mac }}</strong>
              <small>{{ item.message }}</small>
              <em>{{ new Date(item.created_at).toLocaleString("zh-CN", { hour12: false }) }}</em>
            </article>
            <div v-if="!workspace.recentAlerts.value.length" class="empty-copy">
              当前没有最近告警。
            </div>
          </div>
        </article>
      </div>
    </div>
  </section>
</template>

<style scoped>
.overview-stage,
.overview-stage__detail-row,
.alert-list {
  display: grid;
  gap: 18px;
}

.overview-stage {
  width: 100%;
  align-content: start;
}

.overview-stage > * {
  min-width: 0;
}

.overview-stage__detail-row {
  width: 100%;
  grid-template-columns: minmax(0, 1.05fr) minmax(320px, 0.95fr);
  align-items: start;
}

.alerts-panel {
  display: grid;
  gap: 16px;
}

.alerts-panel__head {
  display: flex;
  gap: 14px;
  justify-content: space-between;
  align-items: flex-start;
}

.alerts-panel__head h2 {
  margin: 0;
  color: var(--text-main);
  font-family: var(--font-display);
}

.alert-row {
  padding: 14px 16px;
  border-radius: 20px;
  background: rgba(12, 20, 34, 0.88);
  border: 1px solid rgba(56, 189, 248, 0.1);
  display: grid;
  gap: 6px;
}

.alert-row strong {
  color: var(--text-main);
}

.alert-row small,
.alert-row em,
.empty-copy {
  color: var(--text-sub);
}

@media (max-width: 1180px) {
  .overview-stage__detail-row {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 760px) {
  .alerts-panel__head {
    flex-direction: column;
  }
}
</style>
