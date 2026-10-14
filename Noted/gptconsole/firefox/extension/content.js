(() => {
  if (window.__CHATGPT_TERMINAL_CONTENT__) {
    return;
  }

  window.__CHATGPT_TERMINAL_CONTENT__ = true;

  const RESPONSE_TIMEOUT = 60000;
  const RESPONSE_STABLE_MS = 1500;


  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }


  function getAssistantMessages() {
    return Array.from(
      document.querySelectorAll(
        '[data-markdown-text-style="assistant-message"]'
      )
    );
  }


  function getAssistantSnapshot() {

    const messages = getAssistantMessages();

    const last = messages[messages.length - 1];


    return {
      count: messages.length,
      node: last || null,
      text: last
        ? (last.innerText || "").trim()
        : ""
    };
  }



  async function waitForResponse(before) {

    const start = Date.now();

    let lastText = "";
    let stableSince = 0;
    let responseNode = null;


    while (Date.now() - start < RESPONSE_TIMEOUT) {

      await sleep(300);


      const current = getAssistantSnapshot();


      const isNewResponse =
        current.count > before.count ||
        (
          current.node &&
          current.node !== before.node
        ) ||
        (
          current.text &&
          current.text !== before.text
        );


      if (!isNewResponse || !current.text) {
        continue;
      }


      responseNode = current.node;


      if (current.text !== lastText) {

        lastText = current.text;
        stableSince = Date.now();

        continue;
      }


      if (
        Date.now() - stableSince >= RESPONSE_STABLE_MS
      ) {

        return current.text;

      }


      if (current.node !== responseNode) {

        responseNode = current.node;
        stableSince = Date.now();

      }

    }


    throw new Error(
      "Timeout: response tidak selesai"
    );

  }





  async function chat(text) {


    const input = document.querySelector(
      'div.ProseMirror[data-composer-markdown]'
    );


    if (!input) {
      throw new Error(
        "Input ChatGPT tidak ditemukan"
      );
    }



    // snapshot sebelum kirim
    const before = getAssistantSnapshot();



    input.focus();



    document.execCommand(
      "selectAll",
      false,
      null
    );


    document.execCommand(
      "insertText",
      false,
      text
    );



    await sleep(500);



    // ============================
    // SIMULASI ENTER KEYBOARD
    // ============================

    const el = document.activeElement;



    el.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Enter",
        code: "Enter",
        keyCode: 13,
        which: 13,
        bubbles: true,
        cancelable: true
      })
    );



    el.dispatchEvent(
      new KeyboardEvent("keyup", {
        key: "Enter",
        code: "Enter",
        keyCode: 13,
        which: 13,
        bubbles: true,
        cancelable: true
      })
    );



    return await waitForResponse(before);

  }





async function newSession() {

  const label = document.querySelector(
    "span.text-fade-truncate"
  );


  if (!label || label.innerText.trim() !== "New chat") {
    throw new Error(
      "Tombol New Chat tidak ditemukan"
    );
  }


  const button = label.closest("button");


  if (!button) {
    throw new Error(
      "Parent tombol New Chat tidak ditemukan"
    );
  }


  button.click();


  await sleep(1000);


  return "OK";

}





  browser.runtime.onMessage.addListener(
    message => {


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


    }
  );






  window.addEventListener(
    "__CHATGPT_TERMINAL_CONNECT__",
    () => {


      browser.runtime.sendMessage({
        type: "CONNECT_TAB"
      })

      .then(result => {

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

      })

      .catch(error => {

        console.error(
          "[ChatGPT Terminal] Gagal:",
          error.message
        );

      });


    }
  );





  const script = document.createElement("script");


  script.src = browser.runtime.getURL(
    "inject.js"
  );


  script.onload = () => {
    script.remove();
  };



  (
    document.head ||
    document.documentElement
  )
  .appendChild(script);



  console.log(
    "[ChatGPT Terminal] Content script ready"
  );


})();