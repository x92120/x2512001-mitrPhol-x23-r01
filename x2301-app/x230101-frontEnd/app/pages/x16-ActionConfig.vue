<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { appConfig } from '~/appConfig/config'

const { getAuthHeader } = useAuth()
const actions = ref<any[]>([])
const loading = ref(false)
const filter = ref('')

const fetchActions = async () => {
    loading.value = true
    try {
        const data = await $fetch<any[]>(`${appConfig.apiBaseUrl}/sku-actions/`, {
            headers: getAuthHeader() as Record<string, string>
        })
        actions.value = data || []
    } catch (e) {
        console.error('Error fetching actions:', e)
    } finally {
        loading.value = false
    }
}

const columns = [
  { name: 'action_code', label: 'Action Code', field: 'action_code', sortable: true, align: 'left' as 'left', style: 'width: 150px' },
  { name: 'action_description', label: 'Action Description (Mapped to step)', field: 'action_description', sortable: true, align: 'left' as 'left' },
  { name: 'component_filter', label: 'Component Filter', field: 'component_filter', sortable: true, align: 'left' as 'left' },
  { name: 'updated_at', label: 'System Last Updated', field: 'updated_at', format: (val: string) => val ? new Date(val).toLocaleString() : '', sortable: true, align: 'right' as 'right' }
]

onMounted(() => {
    fetchActions()
})
</script>

<template>
  <q-page padding class="bg-grey-2" style="font-family: 'Sarabun', sans-serif;">
    <div class="row items-center q-mb-md">
      <q-icon name="list_alt" size="24px" color="indigo-9" class="q-mr-sm" />
      <div class="text-h6 text-indigo-10 text-weight-bold">Action Table Definitions</div>
    </div>

    <q-card flat bordered>
        <q-card-section class="row items-center bg-white">
            <q-input outlined dense v-model="filter" placeholder="Search Actions..." class="col-12 col-sm-4 bg-grey-1">
                <template v-slot:append>
                    <q-icon name="search" />
                </template>
            </q-input>
            <q-space />
            <q-btn color="indigo" icon="add" label="New Action" class="q-mr-sm" />
            <q-btn color="grey-8" icon="refresh" outline @click="fetchActions" :loading="loading" />
        </q-card-section>
        
        <q-table
            flat
            :rows="actions"
            :columns="columns"
            row-key="action_code"
            :loading="loading"
            :filter="filter"
            :pagination="{ rowsPerPage: 50 }"
            table-header-class="bg-grey-3 text-weight-bold text-grey-9 text-subtitle2"
            table-class="bg-white"
        >
            <template v-slot:body-cell-action_description="props">
                <q-td :props="props">
                    <div class="text-weight-bold text-indigo-9" style="font-size: 14px;">{{ props.row.action_description }}</div>
                </q-td>
            </template>
            <template v-slot:body-cell-action_code="props">
                <q-td :props="props">
                    <q-badge outline color="indigo-7" class="text-weight-bold q-pa-sm" style="font-size: 13px;">{{ props.row.action_code }}</q-badge>
                </q-td>
            </template>
        </q-table>
    </q-card>
  </q-page>
</template>
