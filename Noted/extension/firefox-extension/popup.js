let currentURL = "";

const SERVER_URL = "http://127.0.0.1:7010/save";

async function loadVideo() {
    let tabs = await browser.tabs.query({
        active: true,
        currentWindow: true
    });

    let tab = tabs[0];

    if (!tab || !tab.url) {
        return;
    }

    try {
        let url = new URL(tab.url);
        let id = url.searchParams.get("v");

        if (id) {
            currentURL = "https://www.youtube.com/watch?v=" + id;
            document.getElementById("url").innerText = currentURL;
        } else {
            document.getElementById("url").innerText = "Tidak ada video";
        }
    } catch (e) {
        document.getElementById("url").innerText = "URL error";
    }
}

async function updateStatus() {
    try {
        let response = await fetch("http://127.0.0.1:7010/data");
        if (!response.ok) throw new Error();
        let item = await response.json();

        document.getElementById("count").innerText =
            item && item.url ? "Server: 1 data" : "Server: 0 data";
    } catch (e) {
        document.getElementById("count").innerText =
            "Server: offline";
    }
}

loadVideo();
updateStatus();

document.getElementById("save").onclick = async () => {
    if (!currentURL) {
        alert("Video tidak ditemukan");
        return;
    }

    let sub = document.getElementById("sub").value;
    let resolution = document.getElementById("resolution").value;

    let item = {
        url: currentURL,
        sub: sub,
        resolution: resolution,
        saved: new Date().toISOString()
    };

    try {
        let response = await fetch(SERVER_URL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(item)
        });

        let result = await response.json();

        if (!response.ok || !result.success) {
            throw new Error(result.error || "Server error");
        }

        updateStatus();
        alert("Data berhasil dikirim ke server");
    } catch (e) {
        console.error(e);
        alert("Gagal mengirim ke server.\nPastikan Python server port 7010 sedang berjalan.");
    }
};

document.getElementById("open").onclick = () => {
    browser.tabs.create({
        url: browser.runtime.getURL("manager.html")
    });
};
