<script setup lang="ts">
import { computed } from "vue";
import type { CommunityRelationTopology } from "../api/client";

const props = defineProps<{
  topology: CommunityRelationTopology | null;
  selectedDeviceMac: string;
}>();

const emit = defineEmits<{
  (event: "select-device", mac: string): void;
}>();

const lanes = computed(() => props.topology?.lanes ?? []);
const unassignedDevices = computed(() => props.topology?.unassigned_devices ?? []);

function isSelectedDevice(id: string) {
  return id === props.selectedDeviceMac;
}
</script>

<template>
  <section class="panel topology-panel">
    <div class="topology-head">
      <div>
        <p class="section-eyebrow">社交关系图谱</p>
        <h2>社区关系拓扑</h2>
        <p class="topology-subtitle">理清社区、老人、家属和手环之间的归属关系，并突出当前选中的实时监护设备。</p>
      </div>
      <div v-if="topology" class="topology-community">
        <span>Community Hub</span>
        <strong>{{ topology.community.label }}</strong>
        <small>{{ topology.community.subtitle }}</small>
      </div>
    </div>

    <div v-if="!lanes.length" class="topology-empty">
      当前还没有可展示的拓扑关系。请先注册老人、家属并完成设备绑定。
    </div>

    <div v-else class="lane-list">
      <article v-for="lane in lanes" :key="lane.elder.id" class="topology-lane">
        <div class="lane-column lane-families">
          <span class="lane-label">家属</span>
          <button
            v-for="family in lane.families"
            :key="family.id"
            type="button"
            class="node-chip node-chip--family"
          >
            <strong>{{ family.label }}</strong>
            <small>{{ family.subtitle }}</small>
          </button>
          <div v-if="!lane.families.length" class="node-chip node-chip--ghost">
            <strong>暂无家属</strong>
            <small>待建立关系</small>
          </div>
        </div>

        <div class="lane-column lane-elder">
          <span class="lane-label">老人</span>
          <div class="node-core" :data-risk="lane.elder.risk_level ?? 'low'">
            <strong>{{ lane.elder.label }}</strong>
            <small>{{ lane.elder.subtitle }}</small>
            <em>{{ lane.elder.status }}</em>
          </div>
        </div>

        <div class="lane-column lane-devices">
          <span class="lane-label">设备</span>
          <button
            v-for="device in lane.devices"
            :key="device.id"
            type="button"
            class="node-chip node-chip--device"
            :class="{ 'node-chip--selected': isSelectedDevice(device.id) }"
            :data-risk="device.risk_level ?? 'low'"
            @click="emit('select-device', device.id)"
          >
            <strong>{{ device.label }}</strong>
            <small>{{ device.subtitle }}</small>
            <em>{{ device.status }}</em>
          </button>
          <div v-if="!lane.devices.length" class="node-chip node-chip--ghost">
            <strong>暂无设备</strong>
            <small>待绑定手环</small>
          </div>
        </div>
      </article>
    </div>

    <div v-if="unassignedDevices.length" class="orphan-strip">
      <span class="lane-label">未归属设备</span>
      <div class="orphan-row">
        <button
          v-for="device in unassignedDevices"
          :key="device.id"
          type="button"
          class="node-chip node-chip--device"
          :class="{ 'node-chip--selected': isSelectedDevice(device.id) }"
          @click="emit('select-device', device.id)"
        >
          <strong>{{ device.label }}</strong>
          <small>{{ device.subtitle }}</small>
          <em>{{ device.status }}</em>
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.topology-panel {
  display: grid;
  gap: 18px;
  background: #ffffff;
}

.topology-head,
.lane-list,
.orphan-row {
  display: grid;
  gap: 16px;
}

.topology-head {
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: start;
}

.topology-head h2 {
  margin: 0;
  font-family: var(--font-display);
  color: var(--text-main);
}

.topology-subtitle {
  margin: 8px 0 0;
  color: var(--text-sub);
  line-height: 1.7;
}

.topology-community {
  display: grid;
  gap: 4px;
  padding: 14px 16px;
  min-width: 220px;
  border-radius: 24px;
  background: #f8fafc;
  color: var(--text-main);
  border: 1px solid var(--line-medium);
}

.topology-community span,
.lane-label {
  font-size: 0.74rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-sub);
}

.topology-community span {
  color: var(--text-sub);
}

.topology-community strong {
  font-size: 1.1rem;
}

.lane-list {
  gap: 20px;
}

.topology-lane {
  display: grid;
  grid-template-columns: minmax(180px, 0.9fr) minmax(220px, 0.8fr) minmax(220px, 1.2fr);
  gap: 22px;
  align-items: center;
  padding: 20px;
  border-radius: 28px;
  background: #ffffff;
  border: 1px solid var(--line-medium);
  box-shadow: 0 4px 16px rgba(15, 23, 42, 0.03);
  position: relative;
}

.topology-lane::before,
.topology-lane::after {
  content: "";
  position: absolute;
  top: 50%;
  height: 1px;
  background: var(--line-medium);
}

.topology-lane::before {
  left: 30%;
  width: 10%;
}

.topology-lane::after {
  right: 30%;
  width: 10%;
}

.lane-column {
  display: grid;
  gap: 10px;
}

.lane-families,
.lane-devices {
  align-content: start;
}

.lane-elder {
  justify-items: center;
}

.node-core,
.node-chip {
  border-radius: 22px;
  border: 1px solid var(--line-medium);
  background: #ffffff;
  padding: 14px 16px;
  display: grid;
  gap: 4px;
  text-align: left;
}

.node-core {
  min-width: 220px;
  justify-items: center;
  text-align: center;
  background: #f8fafc;
}

.node-core[data-risk="high"] {
  background: #fef2f2;
  border-color: rgba(239, 68, 68, 0.3);
}

.node-core[data-risk="medium"] {
  background: #fffbeb;
  border-color: rgba(245, 158, 11, 0.3);
}

.node-chip {
  cursor: default;
}

.node-chip--device {
  cursor: pointer;
  transition: transform 180ms ease, border-color 180ms ease, box-shadow 180ms ease;
}

.node-chip--device:hover,
.node-chip--selected {
  transform: translateY(-1px);
  border-color: var(--brand);
  background: #eff6ff;
  box-shadow: 0 8px 16px rgba(37, 99, 235, 0.08);
}

.node-chip strong,
.node-core strong {
  color: var(--text-main);
  font-size: 0.98rem;
}

.node-chip small,
.node-core small,
.node-chip em,
.node-core em {
  color: var(--text-sub);
  font-style: normal;
  font-size: 0.82rem;
}

.node-chip--ghost {
  background: #f1f5f9;
  border-style: dashed;
}

.orphan-strip {
  display: grid;
  gap: 12px;
  padding-top: 8px;
  border-top: 1px solid var(--line-strong);
}

.orphan-row {
  display: flex;
  flex-wrap: wrap;
}

.topology-empty {
  padding: 20px;
  border-radius: 24px;
  background: #ffffff;
  border: 1px solid var(--line-medium);
  color: var(--text-sub);
}

@media (max-width: 1100px) {
  .topology-head,
  .topology-lane {
    grid-template-columns: 1fr;
  }

  .topology-lane::before,
  .topology-lane::after {
    display: none;
  }

  .lane-elder {
    justify-items: stretch;
  }

  .node-core {
    min-width: 0;
  }
}
</style>
