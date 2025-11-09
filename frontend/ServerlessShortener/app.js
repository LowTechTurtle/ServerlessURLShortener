// app.js
const LINKS_KEY = 'urlShortenerLinks';

const config = {
    createEndpoint: '',
    deleteEndpoint: '',
    redirectEndpoint: ''
};

const links = [];

function loadConfig() {
    if (typeof API_CONFIG !== 'undefined') {
        config.createEndpoint = API_CONFIG.createEndpoint || '';
        config.deleteEndpoint = API_CONFIG.deleteEndpoint || '';
        config.redirectEndpoint = API_CONFIG.redirectEndpoint || '';
    }
}

function loadLinks() {
    const saved = localStorage.getItem(LINKS_KEY);
    if (saved) {
        const parsed = JSON.parse(saved);
        links.length = 0;
        links.push(...parsed);
        renderLinks();
    }
}

function saveLinks() {
    localStorage.setItem(LINKS_KEY, JSON.stringify(links));
}

function showNotification(message, type = 'success') {
    const notification = document.getElementById('notification');
    if (!notification) return;
    notification.textContent = message;
    notification.className = `notification ${type}`;
    notification.classList.remove('hidden');
    
    setTimeout(() => {
        notification.classList.add('hidden');
    }, 3000);
}

function renderLinks() {
    const linksList = document.getElementById('links-list');
    if (!linksList) return;
    
    if (links.length === 0) {
        linksList.innerHTML = '<p class="empty-state">No links created yet. Create your first short link above!</p>';
        return;
    }
    
    linksList.innerHTML = links.map(link => `
        <div class="link-item" data-id="${link.id}">
            <div class="link-info">
                <span class="short">${link.short}</span>
                <span class="long">${link.long}</span>
                <span class="id">ID: ${link.id}</span>
            </div>
            <button class="btn btn-danger delete-btn" data-id="${link.id}">Delete</button>
        </div>
    `).join('');
    
    document.querySelectorAll('.delete-btn').forEach(btn => {
        btn.addEventListener('click', handleDelete);
    });
}

// Get token via auth.js global function; if token missing, auth.js will redirect to login
async function getTokenOrRedirect() {
    if (typeof window.getAuthToken !== 'function') {
        console.error("getAuthToken not available - make sure auth.js loaded first.");
        showNotification('Internal auth error', 'error');
        return null;
    }
    const token = await window.getAuthToken();
    return token;
}

async function handleCreateLink(e) {
    e.preventDefault();
    
    if (!config.createEndpoint) {
        showNotification('API endpoint not configured', 'error');
        return;
    }
    
    const longUrlEl = document.getElementById('long-url');
    if (!longUrlEl) return;
    const longUrl = longUrlEl.value.trim();
    
    if (!longUrl) {
        showNotification('Please enter a URL', 'error');
        return;
    }
    
    const token = await getTokenOrRedirect();
    if (!token) return; // getAuthToken will redirect

    try {
        const response = await fetch(config.createEndpoint, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ long: longUrl })
        });
        
        if (!response.ok) {
            const text = await response.text().catch(()=>'');
            throw new Error(`HTTP error! status: ${response.status} ${text}`);
        }
        
        const data = await response.json();
        
        const shortId = data.id || data.shortId || data.short_id;
        if (!shortId) {
            throw new Error('No ID returned from API');
        }
        
        const shortUrl = `${window.location.origin}/#${shortId}`;
        
        const newLink = {
            id: shortId,
            long: longUrl,
            short: shortUrl,
            createdAt: new Date().toISOString()
        };
        
        links.unshift(newLink);
        saveLinks();
        renderLinks();
        
        document.getElementById('short-link').value = shortUrl;
        document.getElementById('link-id').textContent = shortId;
        document.getElementById('result-section').classList.remove('hidden');
        
        document.getElementById('long-url').value = '';
        
        showNotification('Short link created successfully!', 'success');
        
    } catch (error) {
        console.error('Error creating short link:', error);
        showNotification(`Error creating link: ${error.message}`, 'error');
    }
}

async function handleDelete(e) {
    const linkId = e.target.dataset.id;
    
    if (!config.deleteEndpoint) {
        showNotification('API endpoint not configured', 'error');
        return;
    }
    
    if (!confirm('Are you sure you want to delete this link?')) {
        return;
    }

    const token = await getTokenOrRedirect();
    if (!token) return; // redirect happened
    
    try {
        const response = await fetch(`${config.deleteEndpoint}/${linkId}`, {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ id: linkId })
        });
        
        if (!response.ok) {
            const text = await response.text().catch(()=> '');
            throw new Error(`HTTP error! status: ${response.status} ${text}`);
        }
        
        const index = links.findIndex(link => link.id === linkId);
        if (index !== -1) {
            links.splice(index, 1);
            saveLinks();
            renderLinks();
        }
        
        showNotification('Link deleted successfully!', 'success');
        
    } catch (error) {
        console.error('Error deleting link:', error);
        showNotification(`Error deleting link: ${error.message}`, 'error');
    }
}

function handleCopy() {
    const shortLink = document.getElementById('short-link');
    if (!shortLink) return;
    shortLink.select();
    document.execCommand('copy');
    
    const copyBtn = document.getElementById('copy-btn');
    const originalText = copyBtn.textContent;
    copyBtn.textContent = 'Copied!';
    
    setTimeout(() => {
        copyBtn.textContent = originalText;
    }, 4000);
    
    showNotification('Link copied to clipboard!', 'success');
}

document.addEventListener('DOMContentLoaded', () => {
    loadConfig();
    loadLinks();
    
    const createForm = document.getElementById('create-form');
    if (createForm) createForm.addEventListener('submit', handleCreateLink);

    const copyBtn = document.getElementById('copy-btn');
    if (copyBtn) copyBtn.addEventListener('click', handleCopy);
});

