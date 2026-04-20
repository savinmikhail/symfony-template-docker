<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { api } from './api.js'

const products = ref([])
const isLoading = ref(true)
const isSaving = ref(false)
const errorMessage = ref('')
const form = reactive({
  name: '',
  price: '19.99',
})

const hasProducts = computed(() => products.value.length > 0)

async function loadProducts() {
  isLoading.value = true
  errorMessage.value = ''

  try {
    products.value = await api.products()
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : 'Unable to load products.'
  } finally {
    isLoading.value = false
  }
}

async function createProduct() {
  if (!form.name.trim() || !form.price.trim()) {
    errorMessage.value = 'Name and price are required.'
    return
  }

  isSaving.value = true
  errorMessage.value = ''

  try {
    await api.createProduct({
      name: form.name.trim(),
      price: form.price.trim(),
    })
    form.name = ''
    form.price = '19.99'
    await loadProducts()
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : 'Unable to create product.'
  } finally {
    isSaving.value = false
  }
}

onMounted(loadProducts)
</script>

<template>
  <main class="app-shell">
    <section class="hero">
      <div>
        <p class="eyebrow">
          Symfony + Vue starter
        </p>
        <h1>Product catalog</h1>
      </div>
      <button
        class="ghost-button"
        type="button"
        :disabled="isLoading"
        @click="loadProducts"
      >
        Refresh
      </button>
    </section>

    <form
      class="product-form"
      @submit.prevent="createProduct"
    >
      <label>
        <span>Name</span>
        <input
          v-model="form.name"
          name="name"
          autocomplete="off"
          placeholder="Product name"
        >
      </label>
      <label>
        <span>Price</span>
        <input
          v-model="form.price"
          name="price"
          inputmode="decimal"
          placeholder="19.99"
        >
      </label>
      <button
        type="submit"
        :disabled="isSaving"
      >
        {{ isSaving ? 'Saving...' : 'Create' }}
      </button>
    </form>

    <p
      v-if="errorMessage"
      class="alert"
    >
      {{ errorMessage }}
    </p>

    <section class="table-panel">
      <div
        v-if="isLoading"
        class="empty-state"
      >
        Loading products...
      </div>
      <div
        v-else-if="!hasProducts"
        class="empty-state"
      >
        No products yet.
      </div>
      <table v-else>
        <thead>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Price</th>
            <th>Created</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="product in products"
            :key="product.id"
          >
            <td>{{ product.id }}</td>
            <td>{{ product.name }}</td>
            <td>{{ product.price }}</td>
            <td>{{ new Date(product.createdAt).toLocaleString() }}</td>
          </tr>
        </tbody>
      </table>
    </section>
  </main>
</template>
