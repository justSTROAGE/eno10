(function () {
  document.addEventListener("click", function (e) {
    var btn = e.target.closest("[data-copy]");
    if (btn) {
      var el = document.querySelector(btn.getAttribute("data-copy"));
      if (el && navigator.clipboard) {
        navigator.clipboard.writeText(el.innerText.trim()).then(function () {
          var old = btn.textContent;
          btn.textContent = "Copied";
          setTimeout(function () { btn.textContent = old; }, 1200);
        });
      }
      return;
    }
    var x = e.target.closest(".alert .x");
    if (x) { x.closest(".alert").remove(); }
  });

  document.addEventListener("submit", function (e) {
    var msg = e.target.getAttribute("data-confirm");
    if (msg && !window.confirm(msg)) { e.preventDefault(); }
  });
})();
