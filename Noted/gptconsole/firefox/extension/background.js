(() => {
  const WS_URL = "ws://127.0.0.1:5090";

  let socket = null;
  let connectedTabId = null;
  let reconnectTimer = null;

  function log(...args) {
    console.log("[ChatGPT Terminal]", ...args);
  }

  function connectSocket() {
    if (
      socket &&
      (
        socket.readyState === WebSocket.OPEN ||
        socket.readyState === WebSocket.CONNECTING
      )
    ) {
      return;
    }

    log("Connecting to", WS_URL);

    const ws = new WebSocket(WS_URL);

    socket = ws;

    ws.onopen = () => {
      log("Connected to Python server");
    };

    ws.onmessage = async event => {
      let command;

      try {
        command = JSON.parse(event.data);
      } catch {
        log("Invalid JSON:", event.data);
        return;
      }

      if (!command.id || !command.type) {
        return;
      }

      if (connectedTabId === null) {
        ws.send(JSON.stringify({
          id: command.id,
          ok: false,
          error:
            "Extension belum terhubung. Jalankan connectterminal()"
        }));
        return;
      }

      try {
        const response = await browser.tabs.sendMessage(
          connectedTabId,
          {
            type: command.type,
            id: command.id,
            text: command.text || ""
          }
        );

        if (!response) {
          ws.send(JSON.stringify({
            id: command.id,
            ok: false,
            error: "Tidak ada response dari content script"
          }));

          return;
        }

        ws.send(JSON.stringify(response));
      } catch (error) {
        ws.send(JSON.stringify({
          id: command.id,
          ok: false,
          error: error.message || String(error)
        }));
      }
    };

    ws.onerror = error => {
      log("WebSocket error", error);
    };

    ws.onclose = () => {
      if (socket === ws) {
        socket = null;
      }

      log("Disconnected from Python server");

      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
      }

      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connectSocket();
      }, 1000);
    };
  }

  browser.runtime.onMessage.addListener(
    (message, sender) => {
      if (!message || !message.type) {
        return Promise.resolve({
          ok: false,
          error: "Invalid message"
        });
      }

      if (message.type === "CONNECT_TAB") {
        if (!sender.tab || typeof sender.tab.id !== "number") {
          return Promise.resolve({
            ok: false,
            error: "Tab ID tidak ditemukan"
          });
        }

        connectedTabId = sender.tab.id;

        log(
          "Connected ChatGPT tab:",
          connectedTabId
        );

        connectSocket();

        return Promise.resolve({
          ok: true
        });
      }

      return Promise.resolve({
        ok: false,
        error: "Unknown message"
      });
    }
  );

  browser.tabs.onRemoved.addListener(tabId => {
    if (tabId === connectedTabId) {
      connectedTabId = null;

      log("Connected ChatGPT tab closed");
    }
  });

  connectSocket();

  log("Background ready");
})();