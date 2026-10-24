(function () {
  if (!("mediaSession" in navigator)) return;

  function getTitle() {
    return (
      document.querySelector("heading a")?.textContent?.trim() ||
      document.title
    );
  }

  function getArtwork(audioEl) {
    const url = audioEl.closest("archive")?.dataset?.heroImageUrl;
    if (!url) return [];
    return [{ src: url, sizes: "512x512", type: "image/png" }];
  }

  function setupMediaSession(audioEl) {
    const title = getTitle();
    const artwork = getArtwork(audioEl);

    navigator.mediaSession.metadata = new MediaMetadata({ title, artwork });

    audioEl.addEventListener("play", function () {
      navigator.mediaSession.playbackState = "playing";
      navigator.mediaSession.metadata = new MediaMetadata({ title: getTitle(), artwork: getArtwork(audioEl) });
    });

    audioEl.addEventListener("pause", function () {
      navigator.mediaSession.playbackState = "paused";
    });

    audioEl.addEventListener("ended", function () {
      navigator.mediaSession.playbackState = "none";
    });

    navigator.mediaSession.setActionHandler("play", function () {
      audioEl.play();
    });

    navigator.mediaSession.setActionHandler("pause", function () {
      audioEl.pause();
    });

    navigator.mediaSession.setActionHandler("seekbackward", function (details) {
      audioEl.currentTime = Math.max(
        0,
        audioEl.currentTime - (details.seekOffset || 10)
      );
    });

    navigator.mediaSession.setActionHandler("seekforward", function (details) {
      audioEl.currentTime = Math.min(
        audioEl.duration || Infinity,
        audioEl.currentTime + (details.seekOffset || 10)
      );
    });

    navigator.mediaSession.setActionHandler("stop", function () {
      audioEl.pause();
      audioEl.currentTime = 0;
      navigator.mediaSession.playbackState = "none";
    });
  }

  function init() {
    const audioEls = document.querySelectorAll("archive audio");
    if (audioEls.length === 0) return;

    // Wire up every audio element; OS picks the one currently playing
    audioEls.forEach(function (audioEl) {
      audioEl.addEventListener("play", function () {
        setupMediaSession(audioEl);
      }, { once: true });
    });

    // Pre-register with the first element so metadata appears before playback
    setupMediaSession(audioEls[0]);
  }

  document.addEventListener("turbo:load", init);
})();
