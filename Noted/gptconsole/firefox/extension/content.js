(() => {
  if (window.__CHATGPT_TERMINAL_CONTENT__) {
    return;
  }

  window.__CHATGPT_TERMINAL_CONTENT__ = true;

  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  function getLastAssistantText() {
    const messages = document.querySelectorAll(
      '[data-message-author-role="assistant"] .markdown'
    );

    if (!messages.length) {
      return "";
    }

    return (messages[messages.length - 1].innerText || "").trim();
  }

  async function waitForResponse() {
    const start = Date.now();
    const timeout = 60000;

    let lastText = "";
    let stableSince = 0;

    while (Date.now() - start < timeout) {
      await sleep(500);

      const currentText = getLastAssistantText();

      if (!currentText) {
        continue;
      }

      if (currentText === lastText) {
        if (!stableSince) {
          stableSince = Date.now();
        }

        if (Date.now() - stableSince >= 1500) {
          return currentText;
        }
      } else {
        lastText = currentText;
        stableSince = Date.now();
      }
    }

    throw new Error("Timeout: response tidak stabil dalam 60 detik");
  }

  async function chat(text) {
    const input = document.querySelector("#prompt-textarea");

    if (!input) {
      throw new Error("Input ChatGPT tidak ditemukan");
    }

    input.focus();

    document.execCommand("selectAll", false, null);
    document.execCommand("insertText", false, text);

    await sleep(1000);

    const send = document.querySelector("#composer-submit-button");

    if (!send) {
      throw new Error("Tombol Send tidak ditemukan");
    }

    send.click();

    return await waitForResponse();
  }

  async function newSession() {
    const button = document.querySelector(
      '[data-testid="create-new-chat-button"]'
    );

    if (!button) {
      throw new Error("Tombol New Chat tidak ditemukan");
    }

    button.click();

    await sleep(1000);

    return "OK";
  }

  browser.runtime.onMessage.addListener(message => {
    if (!message || !message.type) {
      return Promise.resolve({
        ok: false,
        id: message && message.id,
        error: "Invalid command"
      });
    }

    if (message.type === "CHAT") {
      return chat(message.text)
        .then(text => ({
          ok: true,
          id: message.id,
          text
        }))
        .catch(error => ({
          ok: false,
          id: message.id,
          error: error.message || String(error)
        }));
    }

    if (message.type === "NEW_SESSION") {
      return newSession()
        .then(text => ({
          ok: true,
          id: message.id,
          text
        }))
        .catch(error => ({
          ok: false,
          id: message.id,
          error: error.message || String(error)
        }));
    }

    return Promise.resolve({
      ok: false,
      id: message.id,
      error: "Unknown command"
    });
  });

  window.addEventListener(
    "__CHATGPT_TERMINAL_CONNECT__",
    () => {
      browser.runtime.sendMessage({
        type: "CONNECT_TAB"
      }).then(result => {
        if (result && result.ok) {
          console.log(
            "[ChatGPT Terminal] Connected this tab"
          );
        } else {
          console.error(
            "[ChatGPT Terminal] Gagal:",
            result && result.error
          );
        }
      }).catch(error => {
        console.error(
          "[ChatGPT Terminal] Gagal:",
          error.message
        );
      });
    }
  );

  const script = document.createElement("script");

  script.src = browser.runtime.getURL("inject.js");

  script.onload = () => {
    script.remove();
  };

  (document.head || document.documentElement)
    .appendChild(script);

  console.log("[ChatGPT Terminal] Content script ready");
})();