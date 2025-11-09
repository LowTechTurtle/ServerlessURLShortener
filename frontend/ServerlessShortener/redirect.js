function getShortIdFromHash() {
    const hash = window.location.hash;
    if (!hash || hash === '#') return null;
    const shortId = hash.replace(/^#/, '');
    return shortId || null;
}

function getRedirectEndpoint() {
    return API_CONFIG.redirectEndpoint;
}

function extractUrlFromText(text) {
    if (!text) return null;
    // find the first http(s) url-like substring
    const m = text.match(/https?:\/\/[^\s'"<>]+/i);
    return m ? m[0] : null;
}

function renderMessage({ title = 'Notice', message = '', link = null, linkText = null }) {
    const linkHtml = link
        ? `<p><a href="${link}" target="_blank" rel="noopener noreferrer" style="color: #667eea; text-decoration: none; font-weight: 600;">${linkText || link}</a></p>`
        : '';
    document.body.innerHTML = `
        <div style="display: flex; justify-content: center; align-items: center; height: 100vh; font-family: sans-serif;">
            <div style="text-align: center; max-width: 760px; padding: 0 16px;">
                <h1>${title}</h1>
                <div style="white-space: pre-wrap; margin-bottom: 12px;">${message}</div>
                ${linkHtml}
                <p><a href="/" style="color: #667eea; text-decoration: none; font-weight: 600;">Go to Home</a></p>
            </div>
        </div>
    `;
}

async function handleRedirect() {
    const shortId = getShortIdFromHash();
    if (!shortId) return;

    const redirectEndpoint = getRedirectEndpoint();
    if (!redirectEndpoint) {
        console.error('Redirect endpoint not configured');
        renderMessage({
            title: 'Configuration Error',
            message: 'The redirect endpoint has not been configured.'
        });
        return;
    }

    // show initial UI
    document.body.innerHTML = `
        <div style="display: flex; justify-content: center; align-items: center; height: 100vh; font-family: sans-serif;">
            <div style="text-align: center;">
                <h2>Redirecting...</h2>
                <p>Please wait while we redirect you.</p>
            </div>
        </div>
    `;

    try {
        const apiUrl = `${redirectEndpoint}${shortId}`;
        window.location.href = apiUrl; // browser will follow the 301/302 normally
        setTimeout(() => {
        throw new Error("Operation timed out after 4 seconds");
        }, 4000);

    } catch (error) {
        console.error('Error handling redirect:', error);
        // If the error itself contains a URL-like string, try to show it
        renderMessage({
            title: 'Error',
            message: `Failed to redirect automatically: ${error.message}`,
        });
    }
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', handleRedirect);
} else {
    handleRedirect();
}
window.addEventListener('hashchange', handleRedirect);
