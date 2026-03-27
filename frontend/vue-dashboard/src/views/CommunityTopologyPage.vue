<script setup lang="ts">
import { computed, toRef } from "vue";

import type { SessionUser } from "../api/client";
import CommunityDeviceInspector from "../components/CommunityDeviceInspector.vue";
import CommunityDeviceRail from "../components/CommunityDeviceRail.vue";
import CommunityRelationTopology from "../components/CommunityRelationTopology.vue";
import PageHeader from "../components/layout/PageHeader.vue";
import { useCommunityWorkspace } from "../composables/useCommunityWorkspace";

const props = defineProps<{
  sessionUser: SessionUser;
}>();

const workspace = useCommunityWorkspace(toRef(props, "sessionUser"));

const pageMeta = computed(() => [
  `关系链 ${workspace.relationTopology.value?.lanes.length ?? 0}`,
  `未归属设备 ${workspace.relationTopology.value?.unassigned_devices.length ?? 0}`,
  `当前设备 ${workspace.selectedDevice.value?.device_mac ?? "无"}`,
]);
</script>

<template>
  <section class="page-stack">
    <PageHeader
      eyebrow="Topology"
      title="设备拓扑"
      description="从老人、家属和设备关系中查看当前归属。这里同样按老人卡片选中对象，再联动右侧拓扑与绑定详情。"
      :meta="pageMeta"
    />

    <CommunityDeviceRail
      :elders="workspace.topRiskElders.value"
      :selected-elder-id="workspace.selectedElderId.value"
      @select="workspace.setSelectedElderId"
    />

    <div class="topology-layout">
      <CommunityRelationTopology
        :topology="workspace.relationTopology.value ?? null"
        :selected-device-mac="workspace.selectedDeviceMac.value"
        @select-device="workspace.setSelectedDeviceMac"
      />
      <CommunityDeviceInspector
        :elder="workspace.selectedElder.value"
        :device="workspace.selectedDevice.value"
      />
    </div>
  </section>
</template>

<style scoped>
.topology-layout {
  display: grid;
  gap: 18px;
  grid-template-columns: minmax(0, 1.35fr) minmax(340px, 0.82fr);
  align-items: start;
}

@media (max-width: 1180px) {
  .topology-layout {
    grid-template-columns: 1fr;
  }
}
</style>
