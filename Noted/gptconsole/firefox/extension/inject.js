(function () {
  if (window.__chatgptTerminalInjected) {
    return;
  }

  window.__chatgptTerminalInjected = true;

  window.connectterminal = function () {
    console.log("[ChatGPT Terminal] Connecting this tab...");

    window.dispatchEvent(
      new CustomEvent("__CHATGPT_TERMINAL_CONNECT__")
    );
  };

  console.log("[ChatGPT Terminal] connectterminal() ready");
})();