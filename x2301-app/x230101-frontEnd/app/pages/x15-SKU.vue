<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { appConfig } from '~/appConfig/config'

const { getAuthHeader } = useAuth()

const skus = ref<any[]>([])
const selectedSku = ref<any>(null)
const skuSteps = ref<any[]>([])
const loadingSteps = ref(false)

const fetchSkus = async () => {
    try {
        const data = await $fetch<any[]>(`${appConfig.apiBaseUrl}/skus/`, {
            headers: getAuthHeader() as Record<string, string>
        })
        skus.value = data || []
    } catch (e) {
        console.error('Error fetching SKUs:', e)
    }
}

const selectSku = async (sku: any) => {
    selectedSku.value = sku
    loadingSteps.value = true
    try {
        const data = await $fetch<any[]>(`${appConfig.apiBaseUrl}/sku-steps/?sku_id=${sku.sku_id}`, {
            headers: getAuthHeader() as Record<string, string>
        })
        skuSteps.value = data || []
    } catch (e) {
        skuSteps.value = []
        console.error('Error fetching SKU steps:', e)
    } finally {
        loadingSteps.value = false
    }
}

const skuStepsByPhase = computed(() => {
    const groups: Record<string, { phase: string, phase_id: string, steps: any[] }> = {}
    for (const step of skuSteps.value) {
        const ph = step.phase_number || '0'
        if (!groups[ph]) groups[ph] = { phase: ph, phase_id: step.phase_id || '', steps: [] }
        groups[ph].steps.push(step)
    }
    const sorted = Object.values(groups).sort((a, b) => String(a.phase).localeCompare(String(b.phase), undefined, { numeric: true }))
    for (const g of sorted) g.steps.sort((a: any, b: any) => (a.sub_step || 0) - (b.sub_step || 0))
    return sorted
})

const expandedPhases = ref<Record<string, boolean>>({})
const togglePhase = (phase: string) => {
    expandedPhases.value[phase] = expandedPhases.value[phase] === false ? true : false
}
const isPhaseExpanded = (phase: string) => {
    return expandedPhases.value[phase] !== false
}

const printSku = () => {
    // Expand all phases before printing to ensure all data is visible
    for (const phaseGroup of skuStepsByPhase.value) {
        expandedPhases.value[phaseGroup.phase] = true
    }
    // Small timeout to allow Vue to render the expansions before popping the print dialog
    setTimeout(() => {
        window.print()
    }, 100)
}

onMounted(() => {
    fetchSkus()
})
</script>

<template>
  <q-page padding class="bg-grey-2" style="font-family: 'Sarabun', sans-serif;">
    <div class="row q-col-gutter-md" style="height: calc(100vh - 100px);">
      <!-- Left Pane (col-3) -->
      <div class="col-12 col-md-3 flex column">
        <q-card class="flex column full-height" flat bordered>
            <q-card-section class="bg-teal-9 text-white q-py-sm">
                <div class="text-subtitle1 text-weight-bold">SKU List ({{ skus.length }})</div>
            </q-card-section>
            <q-list separator class="col scroll bg-white" style="flex: 1;">
                <q-item v-for="sku in skus" :key="sku.id" clickable v-ripple @click="selectSku(sku)" :active="selectedSku?.id === sku.id" active-class="bg-teal-1 text-teal-10">
                <q-item-section avatar>
                    <q-icon name="science" color="teal-7" />
                </q-item-section>
                <q-item-section>
                    <q-item-label class="text-weight-bold" style="font-size: 13px;">{{ sku.sku_id }}</q-item-label>
                    <q-item-label caption style="font-size: 12px;">{{ sku.sku_name || 'No Description' }}</q-item-label>
                </q-item-section>
                </q-item>
            </q-list>
        </q-card>
      </div>

      <!-- Right Pane (col-9) -->
      <div class="col-12 col-md-9 flex column">
        <q-card class="flex column full-height" flat bordered>
            <template v-if="!selectedSku">
                <div class="flex flex-center full-height text-grey-6 text-h6">
                    <q-icon name="arrow_back" class="q-mr-sm" size="md" /> Select a SKU to view and edit details
                </div>
            </template>
            <template v-else>
                <q-card-section class="bg-teal-7 text-white q-py-sm row items-center">
                    <div class="text-h6 text-weight-bold" style="font-size: 18px;">
                        {{ selectedSku.sku_id }} - {{ selectedSku.sku_name }}
                    </div>
                    <q-space />
                    <q-btn outline dense icon="print" @click="printSku" label="Print PDF" class="q-px-md text-weight-bold bg-white text-teal-8" />
                </q-card-section>

                <q-card-section class="col scroll q-pa-sm bg-white">
                    <q-inner-loading :showing="loadingSteps" />
                    
                    <q-markup-table v-if="skuStepsByPhase.length > 0" flat bordered dense separator="cell" style="font-size: 13px;" class="full-width">
                    <thead class="bg-grey-3 text-grey-9">
                        <tr>
                        <th class="text-center text-weight-bold" style="width: 80px;">Process</th>
                        <th class="text-center text-weight-bold" style="width: 60px;">Step</th>
                        <th class="text-left text-weight-bold" style="width: 110px;">Action Code</th>
                        <th class="text-left text-weight-bold">Action</th>
                        <th class="text-left text-weight-bold">RE Code</th>
                        <th class="text-right text-weight-bold">Require</th>
                        <th class="text-left text-weight-bold">Dest</th>
                        <th class="text-right text-weight-bold">Temp</th>
                        <th class="text-right text-weight-bold">Agitator</th>
                        <th class="text-right text-weight-bold">High Shear</th>
                        <th class="text-right text-weight-bold">Brix</th>
                        <th class="text-right text-weight-bold">pH</th>
                        <th class="text-right text-weight-bold">Time</th>
                        <th class="text-center text-weight-bold" style="width: 90px;">Stamp Time</th>
                        <th class="text-center text-weight-bold" style="width: 60px;">Edit</th>
                        </tr>
                    </thead>
                    <tbody>
                        <template v-for="phaseGroup in skuStepsByPhase" :key="phaseGroup.phase">
                        <tr class="bg-teal-1 cursor-pointer" @click="togglePhase(phaseGroup.phase)">
                            <td colspan="15" class="text-weight-bold text-teal-10" style="padding: 6px 12px; font-size: 13px; user-select: none;">
                            <q-icon :name="isPhaseExpanded(phaseGroup.phase) ? 'expand_more' : 'chevron_right'" size="18px" class="q-mr-xs" />
                            Process Phase {{ phaseGroup.phase }}
                            </td>
                        </tr>
                        <tr v-show="isPhaseExpanded(phaseGroup.phase)" v-for="step in phaseGroup.steps" :key="step.id">
                            <td class="text-center text-grey-6">{{ phaseGroup.phase }}</td>
                            <td class="text-center text-weight-bold" style="color: #424242;">{{ step.sub_step }}</td>
                            <td class="text-weight-bold">{{ step.action_code || '-' }}</td>
                            <td>{{ step.action_description || step.action || '-' }}</td>
                            <td class="text-weight-bold text-indigo">
                                {{ step.re_code || '-' }}
                            </td>
                            <td class="text-right"><q-input borderless dense v-model="step.require" input-class="text-right text-blue-9 text-weight-bold" /></td>
                            <td><q-input borderless dense v-model="step.destination" class="text-blue-9 text-weight-bold" /></td>
                            <td class="text-right"><q-input borderless dense v-model="step.temperature" input-class="text-right text-blue-9 text-weight-bold" /></td>
                            <td class="text-right"><q-input borderless dense v-model="step.agitator_rpm" input-class="text-right text-blue-9 text-weight-bold" /></td>
                            <td class="text-right"><q-input borderless dense v-model="step.high_shear_rpm" input-class="text-right text-blue-9 text-weight-bold" /></td>
                            <td class="text-right"><q-input borderless dense v-model="step.brix_sp" input-class="text-right text-blue-9 text-weight-bold" /></td>
                            <td class="text-right"><q-input borderless dense v-model="step.ph_sp" input-class="text-right text-blue-9 text-weight-bold" /></td>
                            <td class="text-right"><q-input borderless dense v-model="step.step_time" input-class="text-right text-blue-9 text-weight-bold" /></td>
                            <td class="text-center"><q-input borderless dense v-model="step.stamp_time" input-class="text-center text-blue-9 text-weight-bold" /></td>
                            <td class="text-center">
                                <q-btn flat round dense icon="save" size="sm" color="blue" />
                            </td>
                        </tr>
                        </template>
                    </tbody>
                    </q-markup-table>
                    <div v-else class="text-center text-grey q-pa-xl">
                        No steps mapped to this SKU.
                    </div>
                </q-card-section>
            </template>
        </q-card>
      </div>
    </div>
  </q-page>
</template>

<style scoped>
@media print {
  /* Hide the application header entirely */
  :global(.q-header) {
    display: none !important;
  }
  
  /* Hide the left SKU list pane */
  .col-md-3 {
    display: none !important;
  }

  /* Expand the right pane to take full print width */
  .col-md-9 {
    width: 100% !important;
    max-width: 100% !important;
    flex: 0 0 100% !important;
  }

  /* Hide elements that shouldn't be printed */
  .q-btn {
    display: none !important;
  }

  /* Reset layout paddings for clean print framing */
  :global(.q-page-container) {
    padding-top: 0 !important;
  }
  .q-page {
    padding: 0 !important;
    min-height: auto !important;
  }
  
  /* Ensure scrolling lists fully render out to the print stream */
  .scroll {
    overflow: visible !important;
    height: auto !important;
  }
  
  /* Eliminate outer card borders for cleaner look */
  .q-card {
    border: none !important;
  }
  
  /* Tweak table inputs to print like plain text */
  ::v-deep .q-field__control {
    background: transparent !important;
  }
  ::v-deep .q-field__native {
    color: #000 !important;
  }
}
</style>
