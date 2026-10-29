<script lang="ts">
	// App connect: a native app opened this tab to get an app password for
	// the signed-in user. The page shows what is asked (the app's name comes
	// from the server, never from the address) and hands the result back to
	// the app only after the user allows it here.
	import '../../auth.css';
	import { page } from '$app/state';
	import { api, ApiError } from '$lib/api/client';
	import type { components } from '$lib/api/v3/openapi';
	import { AUTH_ENDPOINTS, type AppConnectQuery } from '$lib/queries/auth/endpoints';
	import { authStore } from '$lib/stores/authStore.svelte';
	import { appAddress, framed, handBack } from '$lib/utils/appHandBack';
	import { onMount } from 'svelte';
	import { KeyRound, TriangleAlert } from 'lucide-svelte';
	import Button from '$lib/ui/Button.svelte';

	type RequestView = components['schemas']['AppConnectRequestView'];
	type ConnectRequest = components['schemas']['ConnectRequest'];

	// What the app asked for, as it put it in the address; the server checks
	// every field.
	function readRequest(): ConnectRequest {
		const params = page.url.searchParams;
		const field = (key: string) => params.get(key) ?? '';
		return {
			client_id: field('client_id'),
			redirect_uri: field('redirect_uri'),
			code_challenge: field('code_challenge'),
			code_challenge_method: field('code_challenge_method'),
			state: field('state'),
			name: params.get('name')
		};
	}

	function asQuery({ name, ...rest }: ConnectRequest): AppConnectQuery {
		return name === null || name === undefined ? rest : { ...rest, name };
	}

	const request = readRequest();
	const signedInAs = $derived(
		authStore.user?.username_display ?? authStore.user?.username ?? authStore.user?.display_name
	);

	let view = $state<RequestView | null>(null);
	let error = $state<string | null>(null);
	let backToApp = $state<string | null>(null);
	let busy = $state(false);
	let handedBack = $state<string | null>(null);

	function fail(cause: unknown) {
		if (cause instanceof ApiError && cause.status === 404) {
			error = 'Signing in apps from the browser is not turned on for this server.';
			return;
		}
		if (cause instanceof ApiError && cause.status < 500) {
			error = cause.message;
			const details = cause.details as { redirect?: unknown } | null;
			backToApp = appAddress(details?.redirect);
			return;
		}
		error =
			cause instanceof ApiError
				? 'The server could not answer. Try again from the app.'
				: 'Could not reach the server.';
	}

	onMount(async () => {
		if (framed()) {
			error = 'This page cannot be used inside another page.';
			return;
		}
		try {
			view = await api.v3.GET(AUTH_ENDPOINTS.appConnectRequest(asQuery(request)));
		} catch (cause) {
			fail(cause);
		}
	});

	// Both buttons leave for the app within the click, which is what lets
	// the browser hand an app address over.
	async function allow() {
		busy = true;
		try {
			const answer = await api.v3.POST(AUTH_ENDPOINTS.appConnectAuthorize, request);
			const target = appAddress(answer.redirect);
			if (!target) throw new Error('not an app address');
			handedBack = target;
			handBack(target);
		} catch (cause) {
			view = null;
			fail(cause);
		} finally {
			busy = false;
		}
	}

	function cancel() {
		const target = appAddress(view?.cancel_redirect);
		if (!target) return;
		handedBack = target;
		handBack(target);
	}
</script>

<svelte:head>
	<title>Connect an app - DroppedNeedle</title>
</svelte:head>

<div class="min-h-screen bg-base-100 flex items-center justify-center p-4">
	<div class="w-full max-w-md flex flex-col items-center gap-4 text-center">
		<div class="bg-primary/10 rounded-full p-4">
			<KeyRound class="h-10 w-10 text-primary" />
		</div>

		{#if handedBack}
			<p class="text-base-content/70 text-sm">
				Returning to the app. If nothing happens, open it from here.
			</p>
			<Button href={handedBack} variant="primary" size="sm">Open the app</Button>
		{:else if error}
			<div class="flex flex-col items-center gap-3">
				<p class="text-base-content/70 text-sm" role="alert">{error}</p>
				{#if backToApp}
					<Button href={backToApp} variant="outline" size="sm">Back to the app</Button>
				{/if}
			</div>
		{:else if view}
			<h1 class="text-xl font-semibold">Connect {view.client_name}?</h1>
			<p class="text-base-content/80 text-sm">
				<strong>{view.client_name}</strong> wants to use DroppedNeedle as
				<strong>{signedInAs}</strong>.
			</p>
			<dl class="w-full rounded-box bg-base-200 p-3 text-left text-sm">
				{#if view.device_name}
					<dt class="text-base-content/60">Device, as the app reports it</dt>
					<dd class="mb-2 break-words">{view.device_name}</dd>
				{/if}
				<dt class="text-base-content/60">It gets the app-password</dt>
				<dd class="break-words">{view.password_name}</dd>
			</dl>
			<p class="text-base-content/60 text-xs">
				You can revoke it any time under Profile, Connect Apps.
				{#if view.replaces_existing}
					It replaces the app-password of that name you already have.
				{/if}
			</p>
			<div class="alert alert-warning text-left text-sm" role="note">
				<TriangleAlert class="h-4 w-4 shrink-0" />
				<span>Only allow this if you just tapped "Sign in" in this app yourself.</span>
			</div>
			{#if view.at_limit}
				<p class="text-error text-sm" role="alert">
					You have the most app-passwords allowed. Revoke one under Profile, Connect Apps first.
				</p>
			{/if}
			<div class="flex w-full gap-2">
				<Button variant="outline" class="flex-1" onclick={cancel} disabled={busy}>Cancel</Button>
				<Button
					variant="primary"
					class="flex-1"
					onclick={allow}
					loading={busy}
					disabled={busy || view.at_limit}>Allow</Button
				>
			</div>
		{:else}
			<p class="text-base-content/60 text-sm">Checking the request…</p>
			<span class="loading loading-spinner loading-md text-primary"></span>
		{/if}
	</div>
</div>
