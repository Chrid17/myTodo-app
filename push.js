// Replace with your VAPID public key from Supabase function secrets
const VAPID_PUBLIC_KEY = (window.SUPABASE_VAPID_PUBLIC_KEY || '').trim();

async function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) outputArray[i] = rawData.charCodeAt(i);
  return outputArray;
}

export async function registerAndSubscribePush(supabaseUrl, anonKey, userId) {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return { ok: false, reason: 'unsupported' };
  try {
    // Register SW relative to base href (supports GitHub Pages subpath)
    const swPath = new URL('push-sw.js', document.baseURI).pathname;
    const reg = await navigator.serviceWorker.register(swPath);
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      if (!VAPID_PUBLIC_KEY) return { ok: false, reason: 'missing_vapid' };
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: await urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
      });
    }

    // Send subscription to Supabase REST
    const { endpoint, keys } = sub.toJSON();
    await fetch(`${supabaseUrl}/rest/v1/push_subscriptions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`,
        'Prefer': 'resolution=merge-duplicates',
      },
      body: JSON.stringify({
        user_id: userId,
        endpoint,
        p256dh: keys.p256dh,
        auth: keys.auth,
      }),
    });

    return { ok: true };
  } catch (e) {
    return { ok: false, reason: String(e) };
  }
}


