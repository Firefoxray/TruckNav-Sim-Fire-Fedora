<script lang="ts" setup>
defineProps<{
    onClick: () => void;
    isActive?: boolean;
    title?: string;
    ariaLabel?: string;
}>();
</script>

<template>
    <button
        class="option-btn"
        :title="title"
        :aria-label="ariaLabel || title"
        @click.prevent="onClick"
    >
        <slot />
    </button>
</template>

<style
    lang="scss"
    scoped
    src="~/assets/scss/scoped/common/hudButton.scss"
></style>
