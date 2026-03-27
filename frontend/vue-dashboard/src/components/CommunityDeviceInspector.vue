<script setup lang="ts">
import { computed } from "vue";
import type { CommunityDashboardDeviceItem, CommunityDashboardElderItem } from "../api/client";

const props = defineProps<{
  elder: CommunityDashboardElderItem | null;
  device: CommunityDashboardDeviceItem | null;
}>();

const structured = computed(() => props.device?.structured_health ?? props.elder?.structured_health ?? null);

const hasObservedRealtime = computed(() =>
  Boolean(
    props.device?.latest_timestamp
      || props.elder?.latest_timestamp
      || props.device?.heart_rate != null
      || props.device?.blood_oxygen != null
      || props.device?.blood_pressure
      || props.device?.temperature != null
      || props.device?.steps != null
      || props.elder?.heart_rate != null
      || props.elder?.blood_oxygen != null
      || props.elder?.blood_pressure
      || props.elder?.temperature != null,
  ),
);

const showPendingPlaceholder = computed(
  () => props.device?.device_status === "pending" && !hasObservedRealtime.value,
);

const scoreBreakdown = computed(() => [
  {
    label: "最终分",
    value: structured.value?.health_score?.toFixed(1) ?? (props.device?.latest_health_score?.toString() ?? "--"),
  },
  {
    label: "规则分",
    value: structured.value?.rule_health_score?.toFixed(1) ?? "--",
  },
  {
    label: "模型分",
    value: structured.value?.model_health_score?.toFixed(1) ?? "--",
  },
  {
    label: "建议动作",
    value: structured.value?.recommendation_code ?? (props.elder?.device_mac ? "MONITOR" : "BIND_DEVICE"),
  },
]);

const triggerReasons = computed(() =>
  structured.value?.trigger_reasons?.length ? structured.value.trigger_reasons : props.elder?.risk_reasons ?? [],
);

const sosSummary = computed(() => {
  if (!props.device?.sos_active) return null;
  return props.device.active_sos_trigger === "long_press" ? "长按 SOS 求助" : "双击 SOS 求助";
});

const summaryMeta = computed(() => {
  if (!props.elder) {
    return {
      title: "尚未选择老人",
      subtitle: "从上方老人卡片中选择一位监护对象后，这里会显示绑定状态和监护摘要。",
    };
  }

  if (!props.elder.device_mac) {
    return {
      title: props.elder.elder_name,
      subtitle: `${props.elder.apartment} · 当前无设备，请先在移动端绑定手环。`,
    };
  }

  if (props.device?.device_status === "offline") {
    return {
      title: props.elder.elder_name,
      subtitle: `${props.device.device_name} · ${props.elder.device_mac} · 当前离线`,
    };
  }

  if (showPendingPlaceholder.value) {
    return {
      title: props.elder.elder_name,
      subtitle: `${props.device?.device_name ?? "T10-WATCH"} · ${props.elder.device_mac} · 已绑定，等待首包`,
    };
  }

  return {
    title: props.elder.elder_name,
    subtitle: `${props.device?.device_name ?? "T10-WATCH"} · ${props.elder.device_mac} · ${props.elder.apartment}`,
  };
});

const fallbackTag = computed(() => {
  if (!props.elder?.device_mac) return "当前无设备";
  if (props.device?.device_status === "offline") return "设备离线";
  if (showPendingPlaceholder.value) return "等待首包";
  return "当前没有持续异常标签";
});

const fallbackReason = computed(() => {
  if (!props.elder) return "先选择一位老人。";
  if (!props.elder.device_mac) return "这位老人还没有绑定手环。";
  if (props.device?.device_status === "offline") return "设备离线，等待重新上线。";
  if (showPendingPlaceholder.value) return "设备已绑定成功，等待首个实时样本。";
  return "当前还没有明确的触发原因。";
});
</script>

<template>
  <article class="panel inspector-panel" :class="{ 'inspector-panel--sos': device?.sos_active }">
    <div class="inspector-panel__head">
      <div>
        <p class="section-eyebrow">Selected Elder</p>
        <h2>{{ summaryMeta.title }}</h2>
        <p class="panel-subtitle">{{ summaryMeta.subtitle }}</p>
      </div>
      <span class="inspector-panel__score">
        {{ structured?.health_score?.toFixed(1) ?? device?.latest_health_score ?? "--" }}
      </span>
    </div>

    <p v-if="sosSummary" class="inspector-panel__sos-banner">
      当前存在未确认的 SOS 告警：{{ sosSummary }}
    </p>

    <div class="inspector-panel__scores">
      <article v-for="item in scoreBreakdown" :key="item.label" class="score-breakdown-card">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
      </article>
    </div>

    <p v-if="structured?.score_adjustment_reason" class="inspector-panel__note">
      {{ structured.score_adjustment_reason }}
    </p>

    <div class="inspector-panel__tags">
      <span v-if="sosSummary" class="signal-chip signal-chip--sos">
        {{ sosSummary }}
      </span>
      <span v-for="tag in structured?.abnormal_tags ?? []" :key="tag" class="signal-chip">
        {{ tag }}
      </span>
      <span v-if="!(structured?.abnormal_tags?.length) && !sosSummary" class="signal-chip muted">
        {{ fallbackTag }}
      </span>
    </div>

    <ul class="reason-list">
      <li v-if="sosSummary">请优先联系对应老人，并核查现场状态。</li>
      <li v-for="item in triggerReasons" :key="item">{{ item }}</li>
      <li v-if="!triggerReasons.length && !sosSummary">{{ fallbackReason }}</li>
    </ul>
  </article>
</template>

<style scoped>
.inspector-panel {
  display: grid;
  gap: 14px;
}

.inspector-panel--sos {
  border-color: rgba(248, 113, 122, 0.3);
  box-shadow: 0 18px 44px rgba(200, 30, 40, 0.18);
}

.inspector-panel__head {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  align-items: flex-start;
}

.inspector-panel__head h2 {
  margin: 0;
  font-family: var(--font-display);
  color: #e2f0ff;
}

.panel-subtitle {
  margin: 8px 0 0;
  color: #6ea8c8;
  line-height: 1.6;
}

.inspector-panel__score {
  min-width: 82px;
  padding: 12px 14px;
  border-radius: 18px;
  background: rgba(34, 211, 238, 0.1);
  color: #22d3ee;
  text-align: center;
  font-size: 1.18rem;
  font-weight: 700;
  border: 1px solid rgba(34, 211, 238, 0.2);
}

.inspector-panel__sos-banner {
  margin: 0;
  padding: 14px 16px;
  border-radius: 18px;
  background: rgba(248, 113, 122, 0.1);
  border: 1px solid rgba(248, 113, 122, 0.24);
  color: #f87171;
  font-weight: 700;
}

.inspector-panel__scores {
  display: grid;
  gap: 12px;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.score-breakdown-card {
  display: grid;
  gap: 6px;
  padding: 14px 16px;
  border-radius: 18px;
  background: rgba(13, 20, 38, 0.96);
  border: 1px solid rgba(56, 189, 248, 0.1);
}

.score-breakdown-card span {
  color: #4d7a94;
  font-size: 0.85rem;
  font-weight: 600;
}

.score-breakdown-card strong {
  color: #c8e0f4;
  font-size: 1.1rem;
  font-weight: 700;
}

.inspector-panel__note {
  margin: 0;
  padding: 12px 14px;
  border-radius: 16px;
  background: rgba(34, 211, 238, 0.06);
  color: #6ea8c8;
  line-height: 1.7;
  border: 1px solid rgba(34, 211, 238, 0.1);
}

.inspector-panel__tags {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.signal-chip {
  padding: 7px 12px;
  border-radius: 999px;
  background: rgba(34, 211, 238, 0.1);
  color: #22d3ee;
  font-size: 0.82rem;
  font-weight: 600;
  border: 1px solid rgba(34, 211, 238, 0.18);
}

.signal-chip--sos {
  background: rgba(248, 113, 122, 0.12);
  color: #f87171;
  border-color: rgba(248, 113, 122, 0.24);
}

.signal-chip.muted {
  background: rgba(255, 255, 255, 0.04);
  color: #4d7a94;
  border-color: rgba(56, 189, 248, 0.08);
}

.reason-list {
  margin: 0;
  padding-left: 18px;
  display: grid;
  gap: 10px;
  color: #c8e0f4;
  line-height: 1.7;
}

@media (max-width: 760px) {
  .inspector-panel__head {
    flex-direction: column;
  }

  .inspector-panel__scores {
    grid-template-columns: 1fr;
  }
}
</style>
