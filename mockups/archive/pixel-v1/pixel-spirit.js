(() => {
  const canvas = document.getElementById("spiritCanvas");
  if (!canvas) return;

  const ctx = canvas.getContext("2d");
  const variant = document.body.dataset.variant;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const palette = {
    outline: "#24141a",
    deep: "#58251b",
    ember: "#d94a1f",
    orange: "#f26a22",
    amber: "#ffa51f",
    yellow: "#ffd45d",
    cream: "#fff0b8",
    steel: "#687080",
    steelLight: "#a7adba",
    smoke: "#555762",
    red: "#df3b32",
    shadow: "rgba(20, 12, 16, .34)"
  };

  let state = "idle";
  let frame = 0;
  canvas.width = 48;
  canvas.height = 56;
  ctx.imageSmoothingEnabled = false;

  const p = (x, y, w, h, color) => {
    ctx.fillStyle = color;
    ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h));
  };

  const spark = (x, y, color = palette.yellow) => {
    p(x + 1, y, 2, 4, color);
    p(x, y + 1, 4, 2, color);
  };

  const face = (x, y, expression = state) => {
    if (expression === "error") {
      p(x, y, 1, 1, palette.cream); p(x + 2, y + 2, 1, 1, palette.cream);
      p(x + 2, y, 1, 1, palette.cream); p(x, y + 2, 1, 1, palette.cream);
      p(x + 9, y, 1, 1, palette.cream); p(x + 11, y + 2, 1, 1, palette.cream);
      p(x + 11, y, 1, 1, palette.cream); p(x + 9, y + 2, 1, 1, palette.cream);
      return;
    }
    const blink = expression === "idle" && frame % 6 === 5;
    p(x, y, 3, blink ? 1 : 4, palette.outline);
    p(x + 9, y, 3, blink ? 1 : 4, palette.outline);
    if (!blink) {
      p(x + 1, y + 1, 1, 1, palette.cream);
      p(x + 10, y + 1, 1, 1, palette.cream);
    }
  };

  function drawForgeCub(current) {
    const bounce = current === "attention" ? -2 : 0;
    p(12, 50, 25, 3, palette.shadow);
    p(20, 2 + bounce, 5, 3, palette.outline);
    p(16, 5 + bounce, 12, 4, palette.outline);
    p(12, 8 + bounce, 20, 5, palette.outline);
    p(9, 12 + bounce, 26, 15, palette.outline);
    p(12, 8 + bounce, 16, 4, palette.ember);
    p(10, 12 + bounce, 23, 9, palette.orange);
    p(13, 7 + bounce, 8, 8, palette.orange);
    p(19, 3 + bounce, 4, 8, palette.amber);
    p(17, 10 + bounce, 8, 8, palette.yellow);
    p(13, 20 + bounce, 20, 13, palette.amber);
    p(16, 22 + bounce, 14, 9, palette.yellow);
    face(17, 24 + bounce, current);
    p(10, 31, 27, 4, palette.outline);
    p(12, 34, 23, 11, palette.deep);
    p(15, 35, 17, 7, palette.ember);
    p(17, 44, 4, 6, palette.outline);
    p(28, 44, 4, 6, palette.outline);
    p(14, 49, 9, 3, palette.deep);
    p(27, 49, 9, 3, palette.deep);

    const hammerY = current === "working" && frame % 2 ? 28 : 22;
    p(4, hammerY, 4, 15, palette.deep);
    p(1, hammerY - 5, 10, 6, palette.outline);
    p(2, hammerY - 4, 8, 4, palette.steelLight);
    p(8, 34, 6, 4, palette.orange);

    p(32, 34, 10, 10, palette.outline);
    p(34, 34, 6, 3, palette.cream);
    p(33, 37, 4, 5, palette.yellow);
    p(37, 37, 4, 5, palette.amber);
    p(35, 42, 5, 1, palette.orange);

    if (current === "working") {
      spark(3, 15); spark(40, 22, palette.orange);
    } else if (current === "attention") {
      p(40, 8, 4, 11, palette.yellow); p(40, 22, 4, 4, palette.yellow);
    } else if (current === "completed") {
      spark(5, 10); spark(39, 6); spark(41, 28, palette.cream);
    } else if (current === "error") {
      p(37, 9, 5, 3, palette.smoke); p(40, 5, 4, 3, palette.smoke);
    }
  }

  function drawEmberSprite(current) {
    const float = frame % 2;
    p(13, 48, 23, 3, palette.shadow);
    p(20, 3 - float, 5, 5, palette.outline);
    p(16, 7 - float, 13, 5, palette.outline);
    p(12, 11 - float, 21, 6, palette.outline);
    p(9, 16 - float, 28, 19, palette.outline);
    p(12, 11 - float, 17, 7, palette.orange);
    p(16, 6 - float, 8, 9, palette.amber);
    p(20, 3 - float, 4, 8, palette.yellow);
    p(11, 17 - float, 24, 16, palette.orange);
    p(14, 19 - float, 18, 12, palette.yellow);
    p(17, 21 - float, 13, 8, palette.cream);
    face(18, 23 - float, current);
    p(14, 34, 20, 5, palette.outline);
    p(17, 38, 14, 5, palette.deep);
    p(20, 42, 8, 4, palette.ember);
    p(22, 46, 4, 3, palette.orange);

    p(3, 23, 5, 3, palette.amber); p(3, 26, 3, 6, palette.amber);
    p(40, 23, 5, 3, palette.amber); p(42, 26, 3, 6, palette.amber);
    if (current === "working") {
      p(2, 13, 2, 8, palette.steelLight); p(4, 13, 4, 2, palette.steelLight); p(4, 19, 4, 2, palette.steelLight);
      p(40, 13, 2, 8, palette.steelLight); p(36, 13, 4, 2, palette.steelLight); p(36, 19, 4, 2, palette.steelLight);
      spark(37, 34, palette.orange);
    } else if (current === "attention") {
      p(22, 0, 4, 9, palette.yellow); p(22, 11, 4, 4, palette.yellow);
    } else if (current === "completed") {
      spark(6, 8); spark(38, 7); spark(40, 38);
    } else if (current === "error") {
      p(6, 8, 5, 3, palette.smoke); p(38, 5, 5, 3, palette.smoke);
    }
  }

  function drawForgeGolem(current) {
    p(8, 50, 32, 3, palette.shadow);
    p(20, 2, 7, 3, palette.outline);
    p(17, 5, 12, 8, palette.outline);
    p(19, 4, 7, 5, palette.orange);
    p(21, 2, 4, 6, palette.yellow);
    p(13, 12, 22, 7, palette.outline);
    p(10, 18, 28, 22, palette.outline);
    p(13, 14, 22, 6, palette.steel);
    p(12, 20, 24, 17, palette.deep);
    p(15, 22, 18, 13, palette.ember);
    p(17, 23, 14, 10, palette.amber);
    face(18, 25, current);
    p(5, 22, 7, 14, palette.outline);
    p(36, 22, 7, 14, palette.outline);
    p(6, 24, 5, 9, palette.steel);
    p(37, 24, 5, 9, palette.steel);
    p(13, 38, 22, 8, palette.steel);
    p(16, 40, 16, 4, palette.steelLight);
    p(12, 45, 8, 6, palette.outline);
    p(29, 45, 8, 6, palette.outline);
    p(10, 49, 12, 3, palette.steel);
    p(27, 49, 12, 3, palette.steel);

    const hammerUp = current === "working" && frame % 2;
    p(1, hammerUp ? 13 : 28, 6, 5, palette.outline);
    p(2, hammerUp ? 14 : 29, 4, 3, palette.steelLight);
    p(5, hammerUp ? 17 : 31, 3, 12, palette.deep);
    if (current === "working") {
      spark(40, 17); spark(43, 36, palette.orange);
    } else if (current === "attention") {
      p(40, 8, 4, 10, palette.yellow); p(40, 21, 4, 4, palette.yellow);
    } else if (current === "completed") {
      spark(5, 7); spark(39, 7); spark(42, 40);
    } else if (current === "error") {
      p(17, 8, 5, 3, palette.smoke); p(25, 5, 6, 3, palette.smoke);
    }
  }

  const renderers = { a: drawForgeCub, b: drawEmberSprite, c: drawForgeGolem };

  function render() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    renderers[variant](state);
    canvas.dataset.state = state;
    const label = document.getElementById("stateLabel");
    if (label) label.textContent = state;
  }

  function select(group, selected) {
    group.forEach(button => button.setAttribute("aria-pressed", String(button === selected)));
  }

  const stateButtons = [...document.querySelectorAll("[data-state]")].filter(node => node !== canvas);
  stateButtons.forEach(button => button.addEventListener("click", () => {
    state = button.dataset.state;
    select(stateButtons, button);
    render();
  }));

  const sizeButtons = [...document.querySelectorAll("[data-size]")];
  sizeButtons.forEach(button => button.addEventListener("click", () => {
    document.documentElement.style.setProperty("--sprite-size", `${button.dataset.size}px`);
    select(sizeButtons, button);
  }));

  const surfaceButtons = [...document.querySelectorAll("[data-surface-choice]")];
  const viewport = document.querySelector(".viewport");
  surfaceButtons.forEach(button => button.addEventListener("click", () => {
    viewport.dataset.surface = button.dataset.surfaceChoice;
    select(surfaceButtons, button);
  }));

  window.setInterval(() => {
    if (reduceMotion.matches) return;
    frame += 1;
    render();
  }, 420);

  render();
})();
