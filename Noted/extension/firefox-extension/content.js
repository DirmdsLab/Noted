let url = window.location.href;

let params = new URLSearchParams(window.location.search);
let videoId = params.get("v");

browser.runtime.sendMessage({
    url: videoId 
        ? `https://www.youtube.com/watch?v=${videoId}`
        : ""
});