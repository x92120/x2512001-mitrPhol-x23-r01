<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { appConfig } from '~/appConfig/config'
import { useRoute, useRouter } from 'vue-router'

const { getAuthHeader } = useAuth()
const route = useRoute()
const router = useRouter()

// ── State ──
const selectedBatchId = ref<string | null>(null)
const selectedSkuId = ref<string | null>(null)
const batchInfo = ref<any>(null)
const skuSteps = ref<any[]>([])
const loading = ref(false)

// ── Actual PLC Values (simulated) ──
const actualAgitatorRpm = ref(0)
const actualHighShearRpm = ref(0)
const actualTankVolume = ref(0)
const actualTankTemp = ref(0)
let plcInterval: ReturnType<typeof setInterval> | null = null

const startPlcPolling = () => {
    // Simulate real-time PLC values with slight jitter
    const jitter = (base: number, range: number) => +(base + (Math.random() - 0.5) * range).toFixed(1)
    plcInterval = setInterval(() => {
        actualAgitatorRpm.value = jitter(80, 6)
        actualHighShearRpm.value = jitter(3000, 200)
        actualTankVolume.value = jitter(850, 30)
        actualTankTemp.value = jitter(62, 4)
    }, 1500)
    // Set initial values immediately
    actualAgitatorRpm.value = jitter(80, 6)
    actualHighShearRpm.value = jitter(3000, 200)
    actualTankVolume.value = jitter(850, 30)
    actualTankTemp.value = jitter(62, 4)
}

// ── Fetch Batch Info ──
const fetchBatchInfo = async (batchId: string) => {
    loading.value = true
    try {
        const plansResp = await $fetch<any>(`${appConfig.apiBaseUrl}/production-plans/?status=all`, {
             headers: getAuthHeader() as Record<string, string>
        })
        for (const p of plansResp.plans || plansResp) {
            const f = (p.batches || []).find((x: any) => x.batch_id === batchId)
            if (f) {
               batchInfo.value = { ...f, plan_id: p.plan_id, sku_id: p.sku_id, sku_name: p.sku_name, plant: p.plant }
               selectedSkuId.value = p.sku_id
               fetchSkuSteps(p.sku_id)
               break
            }
        }
    } catch (e) {
        console.error(e)
    } finally {
        loading.value = false
    }
}

// ── Fetch SKU steps ──
const fetchSkuSteps = async (skuId: string) => {
    loading.value = true
    try {
        const data = await $fetch<any[]>(`${appConfig.apiBaseUrl}/sku-steps/?sku_id=${skuId}`, {
            headers: getAuthHeader() as Record<string, string>
        })
        // Sort steps globally by phase then sub-step so the index matches the visual order
        const sortedSteps = (data || []).sort((a: any, b: any) => {
            const phA = String(a.phase_number || '0')
            const phB = String(b.phase_number || '0')
            const phCompare = phA.localeCompare(phB, undefined, { numeric: true })
            if (phCompare !== 0) return phCompare
            return (a.sub_step || 0) - (b.sub_step || 0)
        })
        skuSteps.value = sortedSteps
    } catch { skuSteps.value = [] }
    finally { loading.value = false }
}

// ── Group steps by phase ──
const skuStepsByPhase = computed(() => {
    const groups: Record<string, { phase: string, phase_id: string, steps: any[] }> = {}
    for (const step of skuSteps.value) {
        const ph = step.phase_number || '0'
        if (!groups[ph]) groups[ph] = { phase: ph, phase_id: step.phase_id || '', steps: [] }
        groups[ph].steps.push(step)
    }
    const sorted = Object.values(groups).sort((a, b) =>
        String(a.phase).localeCompare(String(b.phase), undefined, { numeric: true })
    )
    for (const g of sorted) g.steps.sort((a: any, b: any) => (a.sub_step || 0) - (b.sub_step || 0))
    return sorted
})

const totalSteps = computed(() => skuSteps.value.length)

// ── Current Operation (simulated) ──
const currentStepIndex = ref(0)
let stepInterval: ReturnType<typeof setInterval> | null = null

const currentStep = computed(() => {
    if (skuSteps.value.length === 0) return null
    return skuSteps.value[currentStepIndex.value % skuSteps.value.length] || null
})

const currentPhaseGroup = computed(() => {
    if (!currentStep.value) return null
    return skuStepsByPhase.value.find(g => g.phase === (currentStep.value?.phase_number || '0')) || null
})

const stepProgress = computed(() => {
    if (skuSteps.value.length === 0) return 0
    return (currentStepIndex.value + 1) / skuSteps.value.length
})

const expandedPhases = ref<Record<string, boolean>>({})
const togglePhase = (phase: string) => {
    expandedPhases.value[phase] = expandedPhases.value[phase] === false ? true : false
}
const isPhaseExpanded = (phase: string) => {
    return expandedPhases.value[phase] !== false
}

const goBack = () => {
    router.push('/x60-CheckForProduction')
}

const printProduction = () => {
    // Expand all phases before printing
    for (const phaseGroup of skuStepsByPhase.value) {
        expandedPhases.value[phaseGroup.phase] = true
    }
    setTimeout(() => {
        window.print()
    }, 100)
}

const isLastStep = computed(() => currentStepIndex.value >= skuSteps.value.length - 1)

// ── Scan Verification ──
const scanInput = ref('')
const scanVerified = ref(false)
const scanError = ref(false)
const scanInputRef = ref<HTMLInputElement | null>(null)

const stepRequiresScan = computed(() => !!currentStep.value?.re_code)

// ── Production Control State ──
const productionStarted = ref(false)
const stepStartTime = ref<number | null>(null)
const currentElapsed = ref(0)
let timerInterval: any = null

const startProduction = () => {
    productionStarted.value = true
    startStepTimer()
}

const startStepTimer = () => {
    if (!productionStarted.value) return
    if (timerInterval) clearInterval(timerInterval)
    stepStartTime.value = Date.now()
    currentElapsed.value = 0
    timerInterval = setInterval(() => {
        if (stepStartTime.value) {
            currentElapsed.value = Math.floor((Date.now() - stepStartTime.value) / 1000)
        }
    }, 1000)
}

const formatDuration = (sec: number) => {
    if (!sec && sec !== 0) return '-'
    const mins = Math.floor(sec / 60)
    const secs = sec % 60
    return `${mins}:${secs.toString().padStart(2, '0')}`
}

watch(currentStepIndex, (newIdx) => {
    if (newIdx < skuSteps.value.length && productionStarted.value) {
        startStepTimer()
    } else {
        if (timerInterval) clearInterval(timerInterval)
    }
}, { immediate: true })

const canProceed = computed(() => {
    if (!productionStarted.value) return false
    if (!stepRequiresScan.value) return true
    return scanVerified.value
})

const onScanInput = () => {
    if (!productionStarted.value) {
        // Any scan can start production if not started
        startProduction()
        scanInput.value = ''
        return
    }
    if (!currentStep.value?.re_code) return
    const scanned = scanInput.value.trim()
    if (!scanned) return
    
    if (scanned === currentStep.value.re_code) {
        scanVerified.value = true
        scanError.value = false
    } else {
        scanVerified.value = false
        scanError.value = true
        setTimeout(() => { scanError.value = false }, 2000)
    }
    scanInput.value = ''
}

// ── Brix / pH Actual Inputs ──
const actualBrix = ref('')
const actualPh = ref('')

const confirmNextStep = () => {
    if (skuSteps.value.length === 0) return
    if (currentStepIndex.value < skuSteps.value.length) {
        // Record stamp time + actual PLC values (YYYY/MM/DD-HH:MM:SS)
        const now = new Date()
        const datePart = now.getFullYear() + '/' + String(now.getMonth() + 1).padStart(2, '0') + '/' + String(now.getDate()).padStart(2, '0')
        const timePart = now.toTimeString().split(' ')[0]
        const formattedStamp = `${datePart}-${timePart}`
        
        const s = skuSteps.value[currentStepIndex.value]
        s.stamp_time = formattedStamp
        s.actual_agitator = actualAgitatorRpm.value
        s.actual_high_shear = actualHighShearRpm.value
        s.actual_volume = actualTankVolume.value
        s.actual_temp = actualTankTemp.value
        if (s.brix_sp) s.actual_brix = actualBrix.value || ''
        if (s.ph_sp) s.actual_ph = actualPh.value || ''
        
        // Record final duration
        s.duration_sec = currentElapsed.value
        
        // If not the last step, move to next
        if (currentStepIndex.value < skuSteps.value.length - 1) {
            currentStepIndex.value++
            // Reset scan state + inputs
            scanVerified.value = false
            scanInput.value = ''
            actualBrix.value = ''
            actualPh.value = ''
            
            // Restart timer will be handled by watch
            
            // Expand phase & scroll
            const step = skuSteps.value[currentStepIndex.value]
            if (step) {
                const phase = step.phase_number || '0'
                expandedPhases.value[phase] = true
            }
            nextTick(() => {
                const el = document.querySelector('.active-step')
                if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' })
                if (stepRequiresScan.value) {
                    scanInputRef.value?.focus()
                }
            })
        } else {
            // Last step confirmed
            currentStepIndex.value++ 
            if (timerInterval) clearInterval(timerInterval)
        }
        scanError.value = false
    }
}

// ── Weight Totals ──
const totalRequireWeight = computed(() => {
    return skuSteps.value.reduce((sum, s) => sum + (Number(s.require) || 0), 0)
})

// Total actual weight = sum of require for completed steps (up to currentStepIndex)
const totalActualWeight = computed(() => {
    return skuSteps.value
        .slice(0, currentStepIndex.value)
        .reduce((sum, s) => sum + (Number(s.require) || 0), 0)
})

const currentStepWeight = computed(() => {
    return Number(currentStep.value?.require) || 0
})

const weightProgress = computed(() => {
    if (totalRequireWeight.value === 0) return 0
    return totalActualWeight.value / totalRequireWeight.value
})

onMounted(() => {
    const qBatch = route.query.batch_id as string
    if (qBatch) {
        selectedBatchId.value = qBatch
        fetchBatchInfo(qBatch)
    }
    startPlcPolling()
})

onUnmounted(() => {
    if (plcInterval) clearInterval(plcInterval)
    if (timerInterval) clearInterval(timerInterval)
})
</script>

<template>
  <q-page class="q-pa-sm" style="height: calc(100vh - 56px); overflow: hidden;">

    <!-- ═══ PAGE HEADER ═══ -->
    <div class="bg-deep-purple-9 text-white q-pa-sm rounded-borders q-mb-sm shadow-2">
      <div class="row justify-between items-center">
        <div class="row items-center q-gutter-sm">
          <q-btn flat round dense icon="arrow_back" color="white" @click="goBack" class="no-print" />
          <q-icon name="precision_manufacturing" size="sm" />
          <div class="text-h6 text-weight-bolder">Production Control</div>
        </div>
        <div class="row items-center q-gutter-sm">
          <template v-if="batchInfo">
            <q-badge color="white" text-color="deep-purple-9" class="q-pa-xs q-px-sm text-weight-bold" style="font-size: 12px;">
              <q-icon name="factory" size="14px" class="q-mr-xs" />{{ batchInfo.plant || '-' }}
            </q-badge>
            <q-badge color="white" text-color="deep-purple-9" class="q-pa-xs q-px-sm text-weight-bold" style="font-size: 12px;">
              <q-icon name="assignment" size="14px" class="q-mr-xs" />{{ batchInfo.plan_id }}
            </q-badge>
            <q-badge color="white" text-color="deep-purple-9" class="q-pa-xs q-px-sm text-weight-bold" style="font-size: 12px;">
              <q-icon name="science" size="14px" class="q-mr-xs" />{{ selectedBatchId }}
            </q-badge>
            <q-badge color="amber-4" text-color="grey-10" class="q-pa-xs q-px-sm text-weight-bold" style="font-size: 12px;">
              {{ (batchInfo.batch_size || 0).toFixed(1) }} kg
            </q-badge>
          </template>
          <div v-else class="text-caption text-deep-purple-2">No Batch Selected</div>
          <q-btn flat round dense icon="print" color="white" @click="printProduction" v-if="skuStepsByPhase.length > 0" class="no-print">
            <q-tooltip>Print PDF</q-tooltip>
          </q-btn>
        </div>
      </div>
    </div>

    <!-- ═══ SKU DETAIL TITLE ═══ -->
    <div v-if="batchInfo" class="bg-teal-7 text-white q-pa-sm rounded-borders q-mb-sm shadow-1" style="flex-shrink: 0;">
      <div class="row items-center">
        <q-icon name="inventory_2" size="24px" class="q-mr-sm" />
        <div>
          <div class="text-subtitle1 text-weight-bold" style="line-height: 1.2;">
            {{ batchInfo?.sku_id }} — {{ batchInfo?.sku_name }}
          </div>
          <div class="text-caption text-teal-2" style="font-size: 11px;">
            Plan: {{ batchInfo?.plan_id }} · Batch: {{ selectedBatchId }} · {{ (batchInfo?.batch_size || 0).toFixed(1) }} kg · {{ totalSteps }} steps · {{ skuStepsByPhase.length }} phases
          </div>
        </div>
        <q-space />
        <q-badge color="white" text-color="teal-9" class="q-pa-xs text-weight-bold" style="font-size: 12px;">
          {{ totalSteps }} steps · {{ skuStepsByPhase.length }} phases
        </q-badge>
      </div>
    </div>

    <!-- ═══ COMBINED STATUS CARD (Phase + Step + Actuals) ═══ -->
    <q-card v-if="selectedBatchId && currentStep" flat bordered class="shadow-1 q-mb-sm" style="height: 250px; flex-shrink: 0; overflow: hidden;">
      <div class="row full-height">
        <!-- Left: Phase & Step Info -->
        <div class="col-4 column justify-center q-pa-sm" style="background: linear-gradient(135deg, #1a237e 0%, #283593 100%); color: white;">
          <div class="row items-center q-mb-xs">
            <div>
              <div class="text-weight-bold" style="font-size: 11px; opacity: 0.7;">PHASE</div>
              <div class="text-weight-bolder" style="font-size: 24px; line-height: 1;">{{ currentStep.phase_number || '-' }}</div>
            </div>
            <q-separator vertical dark class="q-mx-sm" style="opacity: 0.3;" />
            <div>
              <div class="text-weight-bold" style="font-size: 11px; opacity: 0.7;">STEP</div>
              <div class="text-weight-bolder" style="font-size: 32px; line-height: 1;">{{ currentStep.sub_step }}</div>
            </div>
            <q-separator vertical dark class="q-mx-sm" style="opacity: 0.3;" />
            <div class="text-right">
              <div class="text-weight-bold" style="font-size: 11px; opacity: 0.7; color: #ffca28;">TIMER</div>
              <div class="text-weight-bolder text-amber-5" style="font-size: 24px; line-height: 1;">{{ formatDuration(currentElapsed) }}</div>
            </div>
            <q-space />
            <div class="text-right" style="opacity: 0.6; font-size: 12px;">{{ currentStepIndex + 1 }}/{{ totalSteps }}</div>
          </div>
          <q-linear-progress :value="stepProgress" color="amber-4" track-color="white" style="height: 5px; border-radius: 3px; opacity: 0.8;" />

          <!-- Start Button (Only at beginning) -->
          <div v-if="!productionStarted" class="q-mt-sm">
             <q-btn
               color="green-6"
               text-color="white"
               label="START PRODUCTION"
               icon="play_arrow"
               class="full-width text-weight-bolder"
               size="lg"
               unelevated
               @click="startProduction"
               style="height: 60px; font-size: 18px;"
             />
             <div class="text-caption text-center q-mt-xs text-green-3">Click button or Scan to start</div>
          </div>

          <template v-else>
              <!-- Scan Section (when step has re_code) -->
              <div v-if="stepRequiresScan" class="q-mt-sm">
                <div v-if="!scanVerified" class="column">
                  <div class="row items-center q-mb-xs">
                    <q-icon name="qr_code_scanner" size="16px" color="amber-4" class="q-mr-xs" />
                    <span class="text-weight-bold" style="font-size: 12px; color: #ffca28;">SCAN TO CONFIRM</span>
                  </div>
                  <div style="font-size: 11px; opacity: 0.7;" class="q-mb-xs">Expected: <b>{{ currentStep.re_code }}</b></div>
                  <q-input
                    ref="scanInputRef"
                    v-model="scanInput"
                    placeholder="Scan barcode..."
                    dense
                    dark
                    standout="bg-indigo-9"
                    input-class="text-white text-weight-bold"
                    style="font-size: 14px;"
                    @keyup.enter="onScanInput"
                    :error="scanError"
                    :error-message="'Barcode mismatch!'"
                  >
                    <template #prepend>
                      <q-icon name="qr_code_scanner" color="amber-4" />
                    </template>
                  </q-input>
                </div>
                <div v-else class="column items-center q-mt-xs">
                  <q-icon name="check_circle" size="32px" color="green-4" />
                  <div class="text-weight-bold" style="font-size: 13px; color: #66bb6a;">SCAN VERIFIED</div>
                  <div style="font-size: 11px; opacity: 0.8;">{{ currentStep.re_code }}</div>
                </div>
              </div>

              <!-- Manual confirm indicator -->
              <div v-else class="q-mt-sm row items-center">
                <q-icon name="touch_app" size="16px" color="green-4" class="q-mr-xs" />
                <span style="font-size: 12px; color: #81c784;">MANUAL CONFIRM</span>
              </div>

              <q-btn
                :disable="!canProceed || isLastStep"
                color="amber-6"
                text-color="grey-10"
                dense
                unelevated
                :label="isLastStep ? 'Complete' : 'Next ▶'"
                :icon="isLastStep ? 'check_circle' : undefined"
                class="q-mt-sm text-weight-bold full-width"
                style="font-size: 14px; padding: 6px;"
                @click="confirmNextStep"
              />
          </template>
        </div>
        <!-- Right: Step Details grouped as Required vs Actual -->
        <div class="col column q-pa-sm" style="overflow-y: auto;">
          <div class="row items-center q-mb-xs">
            <q-icon name="play_circle" size="28px" color="green-7" class="q-mr-xs" />
            <span class="text-weight-bolder text-grey-9" style="font-size: 22px;">{{ currentStep.action_description || currentStep.action || '-' }}</span>
            <q-badge v-if="currentStep.action_code" color="indigo-6" class="q-ml-sm" style="font-size: 16px; padding: 4px 8px;">{{ currentStep.action_code }}</q-badge>
            <q-badge v-if="currentStep.re_code" color="blue-grey-6" class="q-ml-xs" style="font-size: 16px; padding: 4px 8px;">{{ currentStep.re_code }}</q-badge>
          </div>

          <!-- Info Row: Weights + Require, Destination, Time -->
          <div class="row q-col-gutter-sm q-mb-sm" style="font-size: 20px;">
            <div class="col" style="border-right: 1px solid #e0e0e0;">
              <div class="text-grey-6" style="font-size: 14px;">CURRENT STEP</div>
              <div class="text-weight-bold text-blue-9" style="font-size: 22px;">{{ currentStepWeight.toFixed(3) }} kg</div>
            </div>
            <div class="col" style="border-right: 1px solid #e0e0e0;">
              <div class="text-grey-6" style="font-size: 14px;">ACTUAL BATCHED</div>
              <div class="text-weight-bold text-green-9" style="font-size: 22px;">{{ totalActualWeight.toFixed(3) }} kg</div>
            </div>
            <div class="col" style="border-right: 1px solid #e0e0e0;">
              <div class="text-grey-6" style="font-size: 14px;">TOTAL REQUIRE</div>
              <div class="text-weight-bold text-grey-9" style="font-size: 22px;">{{ totalRequireWeight.toFixed(3) }} kg</div>
            </div>
            <div v-if="currentStep.destination" class="col">
              <div class="text-grey-6" style="font-size: 14px;">DESTINATION</div>
              <div class="text-weight-bold" style="font-size: 22px;">{{ currentStep.destination }}</div>
            </div>
            <div v-if="currentStep.step_time" class="col">
              <div class="text-grey-6" style="font-size: 14px;">TIME</div>
              <div class="text-weight-bold" style="font-size: 22px;">{{ currentStep.step_time }} min</div>
            </div>
            <div v-if="currentStep.brix_sp" class="col">
              <div class="text-grey-6" style="font-size: 12px;">BRIX <span class="text-deep-orange-8">SP: {{ currentStep.brix_sp }}</span></div>
              <q-input v-model="actualBrix" dense outlined placeholder="Actual" type="number" step="0.1"
                input-class="text-weight-bold text-deep-orange-9" style="font-size: 18px; max-width: 120px;">
                <template #append><span style="font-size: 11px; color: #999;">°Bx</span></template>
              </q-input>
            </div>
            <div v-if="currentStep.ph_sp" class="col">
              <div class="text-grey-6" style="font-size: 12px;">pH <span class="text-purple-8">SP: {{ currentStep.ph_sp }}</span></div>
              <q-input v-model="actualPh" dense outlined placeholder="Actual" type="number" step="0.01"
                input-class="text-weight-bold text-purple-9" style="font-size: 18px; max-width: 120px;">
                <template #append><span style="font-size: 11px; color: #999;">pH</span></template>
              </q-input>
            </div>
          </div>

          <!-- Required vs Actual Grid -->
          <div class="row q-col-gutter-xs" style="flex: 1;">
            <!-- Temperature -->
            <div class="col-3">
              <div class="req-act-card" style="border-left: 4px solid #e65100;">
                <div class="text-grey-7 text-weight-bold" style="font-size: 14px;">🌡 TEMPERATURE</div>
                <div class="row justify-between items-end q-mt-xs">
                  <div>
                    <div class="text-grey-5" style="font-size: 12px;">REQUIRE</div>
                    <div class="text-weight-bolder" style="font-size: 28px; line-height: 1; color: #e65100;">{{ currentStep.temperature || '-' }}<span v-if="currentStep.temperature" style="font-size: 16px;">°C</span></div>
                  </div>
                  <div class="text-right">
                    <div class="text-grey-5" style="font-size: 12px;">ACTUAL</div>
                    <div class="text-weight-bolder text-deep-orange-9" style="font-size: 28px; line-height: 1;">{{ actualTankTemp }}<span style="font-size: 16px;">°C</span></div>
                  </div>
                </div>
              </div>
            </div>
            <!-- Agitator -->
            <div class="col-3">
              <div class="req-act-card" style="border-left: 4px solid #00796b;">
                <div class="text-grey-7 text-weight-bold" style="font-size: 14px;">🔄 AGITATOR</div>
                <div class="row justify-between items-end q-mt-xs">
                  <div>
                    <div class="text-grey-5" style="font-size: 12px;">REQUIRE</div>
                    <div class="text-weight-bolder" style="font-size: 28px; line-height: 1; color: #00796b;">{{ currentStep.agitator_rpm || '-' }}<span v-if="currentStep.agitator_rpm" style="font-size: 16px;"> RPM</span></div>
                  </div>
                  <div class="text-right">
                    <div class="text-grey-5" style="font-size: 12px;">ACTUAL</div>
                    <div class="text-weight-bolder text-teal-9" style="font-size: 28px; line-height: 1;">{{ actualAgitatorRpm }}<span style="font-size: 16px;"> RPM</span></div>
                  </div>
                </div>
              </div>
            </div>
            <!-- High Shear -->
            <div class="col-3">
              <div class="req-act-card" style="border-left: 4px solid #7b1fa2;">
                <div class="text-grey-7 text-weight-bold" style="font-size: 14px;">⚡ HIGH SHEAR</div>
                <div class="row justify-between items-end q-mt-xs">
                  <div>
                    <div class="text-grey-5" style="font-size: 12px;">REQUIRE</div>
                    <div class="text-weight-bolder" style="font-size: 28px; line-height: 1; color: #7b1fa2;">{{ currentStep.high_shear_rpm || '-' }}<span v-if="currentStep.high_shear_rpm" style="font-size: 16px;"> RPM</span></div>
                  </div>
                  <div class="text-right">
                    <div class="text-grey-5" style="font-size: 12px;">ACTUAL</div>
                    <div class="text-weight-bolder text-purple-9" style="font-size: 28px; line-height: 1;">{{ actualHighShearRpm }}<span style="font-size: 16px;"> RPM</span></div>
                  </div>
                </div>
              </div>
            </div>
            <!-- Tank Volume -->
            <div class="col-3">
              <div class="req-act-card" style="border-left: 4px solid #1565c0;">
                <div class="text-grey-7 text-weight-bold" style="font-size: 14px;">💧 TANK VOLUME</div>
                <div class="row justify-between items-end q-mt-xs">
                  <div>
                    <div class="text-grey-5" style="font-size: 12px;">REQUIRE</div>
                    <div class="text-weight-bolder" style="font-size: 28px; line-height: 1; color: #1565c0;">{{ currentStep.require ? Number(currentStep.require).toFixed(1) : '-' }}<span v-if="currentStep.require" style="font-size: 16px;"> L</span></div>
                  </div>
                  <div class="text-right">
                    <div class="text-grey-5" style="font-size: 12px;">ACTUAL</div>
                    <div class="text-weight-bolder text-blue-9" style="font-size: 28px; line-height: 1;">{{ actualTankVolume }}<span style="font-size: 16px;"> L</span></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </q-card>

    <!-- ═══ MAIN LAYOUT (1 PANE) ═══ -->
    <div :style="`height: calc(100% - ${selectedBatchId && batchInfo ? '308px' : '60px'}); display: flex; flex-direction: column;`">
      <q-card flat bordered class="shadow-1" style="flex: 1; overflow: hidden; display: flex; flex-direction: column;">
        <template v-if="!selectedBatchId">
          <div class="column items-center justify-center" style="flex: 1;">
             <q-icon name="arrow_back" size="80px" color="grey-4" class="q-mb-md" />
             <div class="text-h6 text-grey-5">Please start production from the "Check for Production" page.</div>
             <q-btn outline color="deep-purple" label="Go to Check for Production" icon="fact_check" class="q-mt-md" @click="goBack" />
          </div>
        </template>
        
        <template v-else>

          <q-card-section class="q-pt-sm q-pb-none col" style="overflow: hidden; display: flex; flex-direction: column;">
            <q-inner-loading :showing="loading" />
            <div v-if="skuStepsByPhase.length === 0 && !loading" class="text-center text-grey q-pa-md">
              No details available for this SKU
            </div>
            
            <q-markup-table v-if="skuStepsByPhase.length > 0" flat bordered dense separator="cell" style="font-size: 14px; flex: 1; overflow: auto;" class="full-width production-table sticky-header-table">
              <thead class="bg-grey-3 text-grey-9">
                <tr>
                  <th class="text-center text-weight-bold" style="width: 50px;">Phase</th>
                  <th class="text-center text-weight-bold" style="width: 40px;">Step</th>
                  <th class="text-left text-weight-bold" style="width: 80px;">Action</th>
                  <th class="text-left text-weight-bold">Description</th>
                  <th class="text-left text-weight-bold">RE Code</th>
                  <th class="text-left text-weight-bold">Dest</th>
                  <th class="text-right text-weight-bold">Require<br><span style="font-size:10px;color:#999;">act/req</span></th>
                  <th class="text-right text-weight-bold">Temp<br><span style="font-size:10px;color:#999;">act/req</span></th>
                  <th class="text-right text-weight-bold">Agitator<br><span style="font-size:10px;color:#999;">act/req</span></th>
                  <th class="text-right text-weight-bold">HighShear<br><span style="font-size:10px;color:#999;">act/req</span></th>
                  <th class="text-right text-weight-bold">Brix<br><span style="font-size:10px;color:#999;">act/req</span></th>
                  <th class="text-right text-weight-bold">pH<br><span style="font-size:10px;color:#999;">act/req</span></th>
                  <th class="text-right text-weight-bold">Timer<br><span style="font-size:10px;color:#999;">act/req</span></th>
                  <th class="text-center text-weight-bold" style="width: 150px;">Stamp Time</th>
                </tr>
              </thead>
              <tbody>
                <template v-for="phaseGroup in skuStepsByPhase" :key="phaseGroup.phase">
                  <tr class="bg-teal-1 cursor-pointer" @click="togglePhase(phaseGroup.phase)">
                    <td colspan="14" class="text-weight-bold text-teal-10" style="padding: 6px 12px; font-size: 12px; user-select: none;">
                      <q-icon :name="isPhaseExpanded(phaseGroup.phase) ? 'expand_more' : 'chevron_right'" size="18px" class="q-mr-xs" />
                      Process Phase {{ phaseGroup.phase }}
                      <span v-if="phaseGroup.phase_id" class="text-grey-7 q-ml-sm" style="font-size: 11px;">({{ phaseGroup.phase_id }})</span>
                      <q-badge color="teal-6" class="q-ml-sm" style="font-size: 10px;">{{ phaseGroup.steps.length }} steps</q-badge>
                    </td>
                  </tr>
                  <template v-for="step in phaseGroup.steps" :key="step.id">
                    <tr v-show="isPhaseExpanded(phaseGroup.phase)"
                      :class="['step-row', { 'active-step': currentStep && step.id === currentStep.id }]">
                      <td class="text-center" :class="currentStep && step.id === currentStep.id ? 'text-weight-bolder' : 'text-grey-6'">{{ phaseGroup.phase }}</td>
                      <td class="text-center text-weight-bold" style="color: #424242;">{{ step.sub_step }}</td>
                      <td class="text-weight-bold">{{ step.action_code || '-' }}</td>
                      <td>{{ step.action_description || step.action || '-' }}</td>
                      <td class="text-weight-bold text-indigo">{{ step.re_code || '-' }}</td>
                      <td>{{ step.destination || '-' }}</td>
                      <td class="text-right">
                        <span class="act-num">{{ step.actual_volume != null ? Number(step.actual_volume).toFixed(1) : '-' }}</span><span class="slash">/</span><span class="req-num">{{ step.require ? Number(step.require).toFixed(3) : '-' }}</span>
                      </td>
                      <td class="text-right">
                        <span class="act-num" style="color: #e65100;">{{ step.actual_temp ?? '-' }}</span><span class="slash">/</span><span class="req-num">{{ step.temperature || '-' }}</span>
                      </td>
                      <td class="text-right">
                        <span class="act-num" style="color: #00796b;">{{ step.actual_agitator ?? '-' }}</span><span class="slash">/</span><span class="req-num">{{ step.agitator_rpm || '-' }}</span>
                      </td>
                      <td class="text-right">
                        <span class="act-num" style="color: #7b1fa2;">{{ step.actual_high_shear ?? '-' }}</span><span class="slash">/</span><span class="req-num">{{ step.high_shear_rpm || '-' }}</span>
                      </td>
                      <td class="text-right">
                        <span class="act-num" style="color: #e65100;">{{ step.actual_brix || '-' }}</span><span class="slash">/</span><span class="req-num">{{ step.brix_sp || '-' }}</span>
                      </td>
                      <td class="text-right">
                        <span class="act-num" style="color: #7b1fa2;">{{ step.actual_ph || '-' }}</span><span class="slash">/</span><span class="req-num">{{ step.ph_sp || '-' }}</span>
                      </td>
                      <td class="text-right">
                        <template v-if="currentStep && step.id === currentStep.id">
                           <span class="act-num text-deep-purple">{{ formatDuration(currentElapsed) }}</span>
                           <span class="slash">/</span>
                           <span class="req-num">{{ step.step_time ? `${step.step_time}:00` : '-' }}</span>
                        </template>
                        <template v-else-if="step.stamp_time">
                           <span class="act-num text-grey-8">{{ formatDuration(step.duration_sec) }}</span>
                           <span class="slash">/</span>
                           <span class="req-num">{{ step.step_time ? `${step.step_time}:00` : '-' }}</span>
                        </template>
                        <template v-else>
                           <span class="act-num">-</span>
                           <span class="slash">/</span>
                           <span class="req-num">{{ step.step_time ? `${step.step_time}:00` : '-' }}</span>
                        </template>
                      </td>
                      <td class="text-center">{{ step.stamp_time || '-' }}</td>
                    </tr>
                  </template>
                </template>
              </tbody>
            </q-markup-table>
          </q-card-section>
        </template>
      </q-card>
    </div>
  </q-page>
</template>

<style scoped>
.active-step {
  background: #fff8e1 !important;
  border-left: 4px solid #ff8f00;
  animation: pulse-bg 2s ease-in-out infinite;
}
.active-step td {
  font-weight: 700 !important;
}
@keyframes pulse-bg {
  0%, 100% { background: #fff8e1; }
  50% { background: #ffecb3; }
}

.actual-row {
  background: #f5f5f5;
  border-top: 1px dashed #e0e0e0;
}
.actual-row td {
  padding-top: 2px !important;
  padding-bottom: 2px !important;
  font-size: 11px;
}
.active-step-actual {
  background: #fff3e0 !important;
}

.act-num {
  font-weight: 700;
}
.req-num {
  color: #999;
  font-weight: 400;
}
.slash {
  color: #bbb;
  margin: 0 1px;
}

.sticky-header-table thead tr th {
  position: sticky;
  top: 0;
  z-index: 10;
  background: #eeeeee !important;
  box-shadow: 0 1px 0 #ccc;
}
/* Ensure the table itself doesn't hide the sticky header */
.sticky-header-table table {
  border-collapse: separate;
  border-spacing: 0;
}

.step-row:hover {
  background: #e8f5e9 !important;
}

.req-act-card {
  background: #fafafa;
  border-radius: 4px;
  padding: 6px 8px;
  height: 100%;
  transition: background 0.2s;
}
.req-act-card:hover {
  background: #f0f0f0;
}

.production-table th {
  font-size: 12px !important;
  position: sticky;
  top: 0;
  z-index: 1;
}

.actual-metric {
  transition: background 0.2s ease;
  padding: 8px;
}
.actual-metric:hover {
  background: #f5f5f5;
}

.spinning-icon {
  animation: spin 2s linear infinite;
}
@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.text-h4 {
  transition: all 0.3s ease;
}

@media print {
  :global(.q-header) {
    display: none !important;
  }
  :global(.q-drawer) {
    display: none !important;
  }
  :global(.q-page-container) {
    padding-top: 0 !important;
    padding-left: 0 !important;
  }
  .q-page {
    padding: 0 !important;
    min-height: auto !important;
    height: auto !important;
  }
  .no-print {
    display: none !important;
  }
  .q-card {
    border: none !important;
    overflow: visible !important;
    height: auto !important;
  }
  .q-card-section {
    overflow: visible !important;
  }
  .production-table {
    font-size: 11px !important;
  }
}
</style>
