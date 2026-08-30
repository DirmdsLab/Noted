const SERVER = "http://127.0.0.1:7010";

async function loadJSON() {
    try {
        let response = await fetch(SERVER + "/data");
        if (!response.ok) throw new Error();

        let item = await response.json();

        document.getElementById("count").innerText =
            item && item.url ? "Total data: 1" : "Total data: 0";

        document.getElementById("json").value =
            item && item.url ? JSON.stringify(item, null, 4) : "{}";
    } catch (e) {
        document.getElementById("count").innerText = "Server offline";
        document.getElementById("json").value =
            "Tidak dapat terhubung ke server port 7010.";
    }
}

loadJSON();

document.getElementById("download").onclick = async () => {
    try {
        let response = await fetch(SERVER + "/data");
        if (!response.ok) throw new Error();

        let item = await response.json();
        let json = JSON.stringify(item || {}, null, 4);

        let blob = new Blob([json], { type: "application/json" });
        let url = URL.createObjectURL(blob);

        let a = document.createElement("a");
        a.href = url;
        a.download = "jsonsave.json";
        a.click();

        setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (e) {
        alert("Server offline.");
    }
};

document.getElementById("clear").onclick = async () => {
    let ok = confirm("Hapus data di server?");

    if (!ok) return;

    try {
        let response = await fetch(SERVER + "/clear", {
            method: "POST"
        });

        if (!response.ok) throw new Error();

        loadJSON();
    } catch (e) {
        alert("Server offline.");
    }
};
