(() => {
    const SERVER = "http://127.0.0.1:7010";
    const WRAPPER_ID = "youtube-saver-inline";

    function getVideoURL() {
        try {
            const url = new URL(location.href);
            const id = url.searchParams.get("v");
            return id ? `https://www.youtube.com/watch?v=${id}` : "";
        } catch {
            return "";
        }
    }

    function setStatus(text, ok = false) {
        const status = document.querySelector(`#${WRAPPER_ID} .ys-status`);
        if (!status) return;
        status.textContent = text;
        status.classList.toggle("ok", ok);
    }

    async function saveVideo() {
        const url = getVideoURL();
        if (!url) {
            setStatus("Bukan video", false);
            return;
        }

        const sub = document.querySelector(`#${WRAPPER_ID} .ys-sub`)?.value || "";
        const resolution = document.querySelector(`#${WRAPPER_ID} .ys-resolution`)?.value || "";

        const item = {
            url,
            sub,
            resolution,
            saved: new Date().toISOString()
        };

        const button = document.querySelector(`#${WRAPPER_ID} .ys-save`);
        if (button) button.disabled = true;
        setStatus("Saving...");

        try {
            const response = await fetch(`${SERVER}/save`, {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify(item)
            });

            const result = await response.json();

            if (!response.ok || !result.success) {
                throw new Error(result.error || "Server error");
            }

            setStatus("Saved ✓", true);
            setTimeout(() => setStatus("", true), 1800);
        } catch (e) {
            console.error("Youtube Saver:", e);
            setStatus("Server offline", false);
        } finally {
            if (button) button.disabled = false;
        }
    }

    function createUI() {
        if (document.getElementById(WRAPPER_ID)) return true;

        const actions = document.querySelector("#top-level-buttons-computed");
        const like = actions?.querySelector("segmented-like-dislike-button-view-model");

        if (!actions || !like) return false;

        const wrapper = document.createElement("div");
        wrapper.id = WRAPPER_ID;
        wrapper.innerHTML = `
            <select class="ys-select ys-sub" aria-label="Subtitle">
                <option value="">Sub</option>
                <option value="en">EN</option>
                <option value="id">ID</option>
                <option value="ja">JA</option>
            </select>
            <select class="ys-select ys-resolution" aria-label="Resolution">
                <option value="">Res</option>
                <option value="4k">4K</option>
                <option value="1080">1080</option>
                <option value="720">720</option>
            </select>
            <button class="ys-save" type="button" title="Save YouTube video">
                Save
            </button>
            <span class="ys-status" aria-live="polite"></span>
        `;

        like.insertAdjacentElement("afterend", wrapper);

        wrapper.querySelector(".ys-save").addEventListener("click", saveVideo);
        return true;
    }

    function watchPage() {
        createUI();

        const observer = new MutationObserver(() => {
            if (!document.getElementById(WRAPPER_ID)) createUI();
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true
        });

        // YouTube SPA navigation can replace the action bar without a full reload.
        document.addEventListener("yt-navigate-finish", () => {
            setTimeout(createUI, 300);
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", watchPage, {once: true});
    } else {
        watchPage();
    }
})();
