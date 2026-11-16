/* ATROX home behaviour: language switch, painted dot fields, tabs, calculator, FAQ, join form.
   Structure ported from an MIT-licensed landing template; no dependencies. */
(function () {
  "use strict";
  var doc = document, root = doc.documentElement;
  var $ = function (s, c) { return (c || doc).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || doc).querySelectorAll(s)); };
  var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var lang = "en";
  var listeners = [];

  /* ---------------------------------------------------------------- language */
  var titles = { en: "ATROX — Strength Score for lifters", tr: "ATROX — Sporcular için Güç Skoru" };
  function setLang(l, save) {
    lang = l;
    root.setAttribute("data-l", l); root.setAttribute("lang", l);
    $$(".switch button").forEach(function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-set") === l)); });
    doc.title = titles[l];
    var email = $("#email"); if (email) email.setAttribute("placeholder", l === "tr" ? "sen@ornek.com" : "you@example.com");
    if (save) { try { localStorage.setItem("atrox-l", l); } catch (e) {} }
    listeners.forEach(function (fn) { fn(); });
  }
  function t(en, tr) { return lang === "tr" ? tr : en; }
  (function initLang() {
    var saved = null; try { saved = localStorage.getItem("atrox-l"); } catch (e) {}
    var guess = (navigator.language || "en").toLowerCase().indexOf("tr") === 0 ? "tr" : "en";
    var asked = new URLSearchParams(location.search).get("lang");
    var pick = asked === "tr" || asked === "en" ? asked : (saved === "tr" || saved === "en" ? saved : guess);
    setLang(pick, false);
    $$(".switch button").forEach(function (b) { b.addEventListener("click", function () { setLang(b.getAttribute("data-set"), true); }); });
  })();

  /* ---------------------------------------------------------------- nav */
  var nav = $("#nav"), menu = $("#menu"), drawer = $("#drawer");
  function onScroll() { nav.setAttribute("data-scrolled", (window.scrollY > 8 || menu.getAttribute("aria-expanded") === "true") ? "true" : "false"); }
  window.addEventListener("scroll", onScroll, { passive: true }); onScroll();
  function setMenu(open) {
    menu.setAttribute("aria-expanded", String(open)); drawer.setAttribute("data-open", String(open)); drawer.setAttribute("aria-hidden", String(!open));
    $$("a", drawer).forEach(function (a) { a.tabIndex = open ? 0 : -1; }); onScroll();
  }
  menu.addEventListener("click", function () { setMenu(menu.getAttribute("aria-expanded") !== "true"); });
  $$('a[href^="#"]').forEach(function (a) {
    a.addEventListener("click", function () {
      setMenu(false);
      if (a.getAttribute("data-focus") === "email") setTimeout(function () { var e = $("#email"); if (e) e.focus({ preventScroll: true }); }, reduced ? 0 : 650);
    });
  });
  if ("IntersectionObserver" in window) {
    var links = $$(".link"), secs = ["product", "how", "calculator", "faq"].map(function (id) { return doc.getElementById(id); });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) links.forEach(function (l) { l.setAttribute("aria-current", l.getAttribute("href") === "#" + e.target.id ? "true" : "false"); }); });
    }, { rootMargin: "-45% 0px -50% 0px" });
    secs.forEach(function (s) { if (s) io.observe(s); });
  }

  /* ---------------------------------------------------------------- painted dot fields */
  function mulberry32(a) { return function () { a |= 0; a = (a + 0x6d2b79f5) | 0; var t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  function randn(rnd) { var u = 0, v = 0; while (!u) u = rnd(); while (!v) v = rnd(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); }
  /* A field is a histogram drawn as dots: dots are sampled from a normal curve, so the share
     of dots left of the "you" dot is the percentile it stands for. */
  var FIELDS = {
    hero0: { seed: 11, count: 5200, r: [0.7, 1.3], mean: 0.5, sigma: 0.2, maxH: 0.74, left: "rgba(150,182,255,.5)", right: "rgba(100,132,232,.3)" },
    hero1: { seed: 23, count: 4200, r: [1.1, 2.0], mean: 0.5, sigma: 0.17, maxH: 0.58, left: "rgba(198,216,255,.82)", right: "rgba(112,148,248,.45)", you: 0.772 },
    hero2: { seed: 37, count: 1700, r: [1.8, 3.4], mean: 0.5, sigma: 0.24, maxH: 0.3, left: "#eaf0ff", right: "#86a3ff" },
    card: { seed: 41, count: 3400, r: [1.0, 2.2], mean: 0.74, sigma: 0.12, maxH: 0.78, left: "rgba(210,226,255,.9)", right: "rgba(88,126,240,.62)", you: 0.772, youOrange: true },
    join0: { seed: 71, count: 4200, r: [0.8, 1.5], mean: 0.5, sigma: 0.21, maxH: 0.56, left: "rgba(160,190,255,.55)", right: "rgba(104,138,236,.32)" },
    join1: { seed: 83, count: 1500, r: [1.8, 3.2], mean: 0.5, sigma: 0.26, maxH: 0.3, left: "#eaf0ff", right: "#86a3ff" }
  };
  function paint(canvas) {
    var o = FIELDS[canvas.getAttribute("data-field")]; if (!o) return;
    var W = canvas.offsetWidth, H = canvas.offsetHeight; if (!W || !H) return;
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    var ctx = canvas.getContext("2d"); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
    var rnd = mulberry32(o.seed), youX = o.you != null ? o.mean + o.sigma * o.you : null;
    var bell = function (x) { return Math.exp(-0.5 * Math.pow((x - o.mean) / o.sigma, 2)); };
    for (var i = 0; i < o.count; i++) {
      var x = o.mean + o.sigma * randn(rnd); if (x < -0.05 || x > 1.05) continue;
      var h = Math.max(bell(x), 0.02) * o.maxH * H;
      var y = H - Math.pow(rnd(), 0.55) * h - rnd() * 2;
      ctx.fillStyle = youX != null && x > youX ? o.right : (youX == null ? (x < o.mean ? o.left : o.right) : o.left);
      ctx.beginPath(); ctx.arc(x * W, y, o.r[0] + rnd() * (o.r[1] - o.r[0]), 0, 6.2832); ctx.fill();
    }
    if (youX != null) {
      var yy = H - bell(youX) * o.maxH * H - 8;
      ctx.fillStyle = "#fe8500"; ctx.strokeStyle = "#fff"; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.arc(youX * W, yy, 7, 0, 6.2832); ctx.fill(); ctx.stroke();
    }
    canvas.setAttribute("data-drawn", "true");
  }
  var canvases = $$("canvas[data-field]"), rt;
  function paintAll() { canvases.forEach(paint); }
  paintAll();
  if (doc.fonts && doc.fonts.ready) doc.fonts.ready.then(function () { /* sizes are CSS-driven; repaint once layout settles */ paintAll(); });
  window.addEventListener("resize", function () { clearTimeout(rt); rt = setTimeout(paintAll, 200); });

  /* hero parallax + plate pops */
  var stage = $("#stage");
  if (stage && !reduced) {
    stage.addEventListener("pointermove", function (e) {
      var r = stage.getBoundingClientRect();
      stage.style.setProperty("--px", ((e.clientX - r.left) / r.width - 0.5) * 2);
      stage.style.setProperty("--py", ((e.clientY - r.top) / r.height - 0.5) * 2);
    });
    stage.addEventListener("pointerleave", function () { stage.style.setProperty("--px", 0); stage.style.setProperty("--py", 0); });
  }
  var POPS = { squat: ["Squat 140 kg → 78", "Squat 140 kg → 78"], deadlift: ["Deadlift 180 kg → 71", "Deadlift 180 kg → 71"] };
  $$(".plate").forEach(function (p) {
    p.addEventListener("click", function () {
      p.setAttribute("data-spin", "true");
      var old = $(".pop", p); if (old) old.remove();
      var pop = doc.createElement("span"); pop.className = "pop"; pop.textContent = t("Sample · ", "Örnek · ") + POPS[p.getAttribute("data-pop")][0];
      p.appendChild(pop);
      setTimeout(function () { p.removeAttribute("data-spin"); if (pop.parentNode) pop.remove(); }, 1800);
    });
  });

  /* ---------------------------------------------------------------- reveal on scroll */
  if ("IntersectionObserver" in window && !reduced) {
    var rvIo = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.remove("pre"); rvIo.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -8% 0px" });
    $$("[data-rv]").forEach(function (el) {
      if (el.getBoundingClientRect().top > window.innerHeight * 0.92) { el.classList.add("rv", "pre"); rvIo.observe(el); }
    });
  }

  /* ---------------------------------------------------------------- tabs */
  var uc = $("#uc"), tabs = $$(".tab"), panels = $$(".card"), cur = 0;
  function selectTab(i, focus) {
    cur = i;
    tabs.forEach(function (tb, k) {
      var on = k === i; tb.setAttribute("aria-selected", String(on)); tb.tabIndex = on ? 0 : -1;
      panels[k].setAttribute("data-on", String(on)); panels[k].setAttribute("aria-hidden", String(!on));
      var a = $(".more", panels[k]); if (a) a.tabIndex = on ? 0 : -1;
    });
    if (focus) tabs[i].focus();
  }
  tabs.forEach(function (tb, i) {
    tb.addEventListener("click", function () { selectTab(i); });
    tb.addEventListener("keydown", function (e) {
      var n = tabs.length, k = null;
      if (e.key === "ArrowDown" || e.key === "ArrowRight") k = (i + 1) % n;
      else if (e.key === "ArrowUp" || e.key === "ArrowLeft") k = (i + n - 1) % n;
      else if (e.key === "Home") k = 0; else if (e.key === "End") k = n - 1;
      if (k !== null) { e.preventDefault(); selectTab(k, true); }
    });
    $(".tabbar", tb).addEventListener("animationend", function () { if (cur === i) selectTab((i + 1) % tabs.length); });
  });
  ["pointerenter", "focusin"].forEach(function (ev) { uc.addEventListener(ev, function () { uc.setAttribute("data-paused", "true"); }); });
  ["pointerleave", "focusout"].forEach(function (ev) { uc.addEventListener(ev, function () { uc.setAttribute("data-paused", "false"); }); });

  /* ---------------------------------------------------------------- coach switch (demo) */
  var sw = $("#coachSwitch"), swl = $("#coachLabel");
  if (sw) sw.addEventListener("click", function () {
    var on = sw.getAttribute("aria-checked") !== "true"; sw.setAttribute("aria-checked", String(on));
    swl.innerHTML = on
      ? '<span lang="en">On: you agreed</span><span lang="tr">Açık: sen onayladın</span>'
      : '<span lang="en">Off until you agree</span><span lang="tr">İzne kadar kapalı</span>';
  });

  /* ---------------------------------------------------------------- calculator (illustration only) */
  var LIFTS = { squat: { m: 1.28, s: 0.40, def: 140 }, bench: { m: 1.08, s: 0.42, def: 100 }, deadlift: { m: 1.80, s: 0.40, def: 180 } };
  var lift = "squat", bw = $("#bw"), lw = $("#lw"), svg = $("#chartSvg");
  function erf(x) { var s = x < 0 ? -1 : 1; x = Math.abs(x); var tt = 1 / (1 + 0.3275911 * x); var y = 1 - (((((1.061405429 * tt - 1.453152027) * tt) + 1.421413741) * tt - 0.284496736) * tt + 0.254829592) * tt * Math.exp(-x * x); return s * y; }
  function phi(z) { return 0.5 * (1 + erf(z / Math.SQRT2)); }
  function fmt(n, d) { return n.toLocaleString(lang === "tr" ? "tr-TR" : "en-US", { minimumFractionDigits: d, maximumFractionDigits: d }); }
  var ZR = 3.2, CW = 600, CH = 280;
  function sx(z) { return ((z + ZR) / (2 * ZR)) * CW; }
  function sy(z) { return CH - 24 - Math.exp(-0.5 * z * z) * 196; }
  function buildChart(z) {
    var zc = Math.max(-ZR, Math.min(ZR, z)), pts = [], area = [], i, zz;
    for (i = 0; i <= 120; i++) { zz = -ZR + (i / 120) * 2 * ZR; pts.push((i ? "L" : "M") + sx(zz).toFixed(1) + " " + sy(zz).toFixed(1)); }
    area.push("M" + sx(-ZR) + " " + (CH - 24));
    for (i = 0; i <= 120; i++) { zz = -ZR + (i / 120) * 2 * ZR; if (zz > zc) break; area.push("L" + sx(zz).toFixed(1) + " " + sy(zz).toFixed(1)); }
    area.push("L" + sx(zc).toFixed(1) + " " + sy(zc).toFixed(1), "L" + sx(zc).toFixed(1) + " " + (CH - 24), "Z");
    svg.innerHTML =
      '<path d="M0 ' + (CH - 24) + 'H' + CW + '" stroke="rgba(255,255,255,.22)" vector-effect="non-scaling-stroke"/>' +
      '<path d="' + area.join("") + '" fill="rgba(143,176,255,.38)"/>' +
      '<path d="' + pts.join("") + '" fill="none" stroke="#bcd0ff" stroke-width="2.2" stroke-linecap="round" vector-effect="non-scaling-stroke"/>' +
      '<path d="M' + sx(zc).toFixed(1) + ' 6V' + (CH - 24) + '" stroke="#fe8500" stroke-width="2.4" vector-effect="non-scaling-stroke"/>';
    var chart = $("#chart"), dot = $("#chartDot", chart);
    if (!dot) { dot = doc.createElement("span"); dot.id = "chartDot"; dot.className = "chartdot"; chart.appendChild(dot); }
    dot.style.left = (sx(zc) / CW) * 100 + "%"; dot.style.top = (sy(zc) / CH) * 100 + "%";
    var lab = $("#chartPct"); lab.style.left = Math.max(9, Math.min(91, (sx(zc) / CW) * 100)) + "%";
  }
  function setFill(el) { el.style.setProperty("--fill", ((el.value - el.min) / (el.max - el.min)) * 100 + "%"); }
  function calc() {
    var L = LIFTS[lift], b = +bw.value, w = +lw.value, r = w / b;
    var z = (Math.log(r) - Math.log(L.m)) / L.s, p = Math.max(1, Math.min(99, Math.round(phi(z) * 100)));
    $("#bwOut").textContent = fmt(b, 0) + " kg"; $("#lwOut").textContent = fmt(w, w % 1 ? 1 : 0) + " kg";
    $("#pctOut").textContent = p; $("#chartPct").textContent = p; $("#ratioOut").textContent = fmt(r, 2) + "×";
    $("#compare").innerHTML = t(
      "At " + fmt(r, 2) + "× body weight you would out-lift about <b>" + p + "</b> of 100 lifters in this illustration.",
      "Vücut ağırlığının " + fmt(r, 2) + " katını kaldırıyorsun. Bu çizimde 100 sporcudan yaklaşık <b>" + p + "</b> kişiyi geçersin.");
    $("#xLo").textContent = fmt(L.m * Math.exp(-L.s * ZR), 2) + "×";
    $("#xMid").textContent = t("Median ", "Medyan ") + fmt(L.m, 2) + "×";
    $("#xHi").textContent = fmt(L.m * Math.exp(L.s * ZR), 2) + "×";
    svg.setAttribute("aria-label", t("Distribution of lifters, you are at percentile " + p, "Sporcuların dağılımı, yüzdelik dilimin " + p));
    setFill(bw); setFill(lw); buildChart(z);
  }
  $$("#liftSeg button").forEach(function (btn) {
    btn.addEventListener("click", function () {
      lift = btn.getAttribute("data-lift");
      $$("#liftSeg button").forEach(function (x) { x.setAttribute("aria-pressed", String(x === btn)); });
      lw.value = LIFTS[lift].def; calc();
    });
  });
  bw.addEventListener("input", calc); lw.addEventListener("input", calc);
  listeners.push(calc); calc();

  /* ---------------------------------------------------------------- faq */
  $$(".q").forEach(function (q) {
    q.addEventListener("click", function () {
      var open = q.getAttribute("aria-expanded") === "true";
      $$(".q").forEach(function (o) {
        var a = doc.getElementById(o.getAttribute("aria-controls")), on = o === q && !open;
        o.setAttribute("aria-expanded", String(on)); a.setAttribute("data-open", String(on)); a.setAttribute("aria-hidden", String(!on));
      });
    });
  });

  /* ---------------------------------------------------------------- join (opens the mail app until a form backend exists) */
  var form = $("#joinForm"), note = $("#joinNote"), email = $("#email");
  function say(msg, err) { note.textContent = msg; note.setAttribute("data-state", err ? "error" : "idle"); }
  form.addEventListener("submit", function (e) {
    e.preventDefault();
    var v = email.value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v)) {
      say(t("That email does not look right.", "Bu e-posta doğru görünmüyor."), true); email.setAttribute("aria-invalid", "true");
      form.setAttribute("data-state", "error"); setTimeout(function () { form.removeAttribute("data-state"); }, 500); return;
    }
    email.removeAttribute("aria-invalid");
    say(t("Your mail app should open. Send the message to join the list.", "E-posta uygulaman açılmalı. Listeye girmek için mesajı gönder."), false);
    location.href = "mailto:hello@atrox.online?subject=" + encodeURIComponent("ATROX waiting list") + "&body=" + encodeURIComponent("Please add " + v + " to the waiting list.");
  });
  email.addEventListener("input", function () { if (note.textContent) say("", false); });
})();
