// Котик как SVG в дизайн-координатах 260×230 плюс его «характер»:
// лапки, настроение, пузырьки, что держит. Без Tauri — чистый DOM,
// используется и в окне котика, и в превью настроек.
(function () {
  const SVG_NS = 'http://www.w3.org/2000/svg';

  const FURS = {
    ginger: { fur: '#F2A645', belly: '#FFF2DB', stripe: '#D17824', eye: '#292421', outline: 'rgba(0,0,0,0.55)', title: 'Рыжий' },
    gray: { fur: '#9EA3AD', belly: '#E0E3E8', stripe: '#6B707D', eye: '#292421', outline: 'rgba(0,0,0,0.55)', title: 'Серый' },
    black: { fur: '#303038', belly: '#54545E', stripe: null, eye: '#FAC733', outline: 'rgba(255,255,255,0.55)', title: 'Чёрный' },
    white: { fur: '#F5F2ED', belly: '#FFFFFF', stripe: null, eye: '#408CD9', outline: 'rgba(0,0,0,0.55)', title: 'Белый' },
  };
  const EYES = {
    auto: { color: null, title: 'По окрасу' },
    green: { color: '#4DB366', title: 'Зелёные' },
    blue: { color: '#408CD9', title: 'Голубые' },
    amber: { color: '#FAC733', title: 'Янтарные' },
    brown: { color: '#292421', title: 'Карие' },
  };
  const KEYBOARDS = {
    dark: { base: '#3B404D', keys: 'rgba(255,255,255,0.35)', title: 'Тёмная' },
    light: { base: '#D1D4DB', keys: 'rgba(0,0,0,0.25)', title: 'Светлая' },
    pink: { base: '#F2ADC7', keys: 'rgba(255,255,255,0.6)', title: 'Розовая' },
  };
  const ACCESSORIES = { none: 'Без всего', bow: 'Бантик', glasses: 'Очки', hat: 'Шапка', scarf: 'Шарф' };
  const SIZES = [
    { id: 's', title: 'S', scale: 0.7 },
    { id: 'm', title: 'M', scale: 1.0 },
    { id: 'l', title: 'L', scale: 1.4 },
    { id: 'xl', title: 'XL', scale: 2.0 },
  ];
  const MOODS = {
    normal: { title: 'спокойный', emoji: '😺' },
    happy: { title: 'довольный', emoji: '😸' },
    sleepy: { title: 'спит', emoji: '😴' },
    grumpy: { title: 'ворчит', emoji: '😾' },
    excited: { title: 'в ударе', emoji: '🙀' },
  };
  const IDLE_PHRASES = [
    'мяу', 'я не помогаю, я тапаю', 'это не баг, это фича', 'коммитить будешь?', 'мур-р',
    'дай скриншот подержать', 'кто тут хороший разработчик?', 'а перерыв?', 'тесты зелёные?', 'мяу-мяу (одобряю)',
  ];
  const FAST_PHRASES = ['быстрее!', 'ого!', 'лапки горят 🔥', 'не успеваю!', 'ты робот?'];

  // Область картинки в лапках (дизайн-координаты) — для перетаскивания наружу.
  const HELD_RECT = { x: 75, y: 125, width: 110, height: 78 };

  function el(name, attrs, children) {
    const node = document.createElementNS(SVG_NS, name);
    if (attrs) for (const [k, v] of Object.entries(attrs)) if (v !== null && v !== undefined) node.setAttribute(k, v);
    if (children) for (const c of children) node.appendChild(c);
    return node;
  }
  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

  // Клавиши ноутбука: 3 ряда по 14, 13, 12 штук.
  function buildKeys(group) {
    group.replaceChildren();
    for (let row = 0; row < 3; row++) {
      const n = 14 - row;
      const width = n * 8 + (n - 1) * 3;
      const start = 130 - width / 2;
      for (let i = 0; i < n; i++) {
        group.appendChild(el('rect', { x: start + i * 11, y: 196 + row * 9, width: 8, height: 6, rx: 1.5 }));
      }
    }
  }

  function earPath(mirrored) {
    const tip = mirrored ? 6.6 : -6.6;
    const c1 = mirrored ? -13 : -20;
    const c2 = mirrored ? 20 : 13;
    return `M-22,25 Q${c1},-10 ${tip},-25 Q${c2},-10 22,25 Z`;
  }
  function innerEarPath(mirrored) {
    const tip = mirrored ? 3.6 : -3.6;
    const c1 = mirrored ? -7 : -11;
    const c2 = mirrored ? 11 : 7;
    return `M-12,23 Q${c1},3 ${tip},-5 Q${c2},3 12,23 Z`;
  }

  class CatRenderer {
    constructor(container, options = {}) {
      this.container = container;
      this.options = options;
      this.settings = { fur: 'ginger', accessory: 'none', eyeColor: 'auto', keyboard: 'dark', mirrored: false, opacity: 1, bubbles: true };
      this.state = {
        leftDown: false, rightDown: false, happiness: 0.6, mood: 'normal', blinking: false, eating: false,
        held: null, lastActivity: Date.now(), petBoostUntil: 0, lastRandomBubble: Date.now(), tapsSinceBubble: 0,
      };
      this.timers = { left: null, right: null, bubble: null };
      this.onMoodChange = options.onMoodChange || null;
      this.build();
      this.applySettings(this.settings);
      this.render();
      this.scheduleBlink();
    }

    // MARK: - Сборка SVG

    build() {
      const svg = el('svg', { viewBox: '0 0 260 230', class: 'cat-svg', preserveAspectRatio: 'xMidYMid meet' });
      const defs = el('defs');
      const filter = el('filter', { id: 'held-shadow', x: '-20%', y: '-20%', width: '140%', height: '140%' });
      filter.appendChild(el('feDropShadow', { dx: 0, dy: 2, stdDeviation: 3, 'flood-color': 'rgba(0,0,0,0.3)' }));
      defs.appendChild(filter);
      svg.appendChild(defs);

      const body = el('g', { id: 'cat-body' });
      this.n = {};
      const n = this.n;

      n.tail = el('path', { d: 'M190,185 C238,192 252,150 240,118', fill: 'none', 'stroke-width': 16, 'stroke-linecap': 'round', class: 'tail' });
      body.appendChild(n.tail);
      n.body = el('ellipse', { cx: 130, cy: 166, rx: 75, ry: 52.5 });
      body.appendChild(n.body);
      n.belly = el('ellipse', { cx: 130, cy: 180, rx: 43, ry: 32 });
      body.appendChild(n.belly);

      n.earL = el('g', { transform: 'translate(90,58) rotate(-14)' });
      n.earLOuter = el('path', { d: earPath(false) });
      n.earLInner = el('path', { d: innerEarPath(false), transform: 'translate(0,9)', fill: '#FFB8C2' });
      n.earL.append(n.earLOuter, n.earLInner);
      n.earR = el('g', { transform: 'translate(170,58) rotate(14)' });
      n.earROuter = el('path', { d: earPath(true) });
      n.earRInner = el('path', { d: innerEarPath(true), transform: 'translate(0,9)', fill: '#FFB8C2' });
      n.earR.append(n.earROuter, n.earRInner);
      body.append(n.earL, n.earR);

      n.head = el('circle', { cx: 130, cy: 98, r: 56 });
      body.appendChild(n.head);

      n.stripes = el('g');
      n.stripes.append(
        el('rect', { x: 108.5, y: 47, width: 7, height: 22, rx: 3.5, transform: 'rotate(-18 112 58)' }),
        el('rect', { x: 126.5, y: 41, width: 7, height: 26, rx: 3.5 }),
        el('rect', { x: 144.5, y: 47, width: 7, height: 22, rx: 3.5, transform: 'rotate(18 148 58)' }),
      );
      body.appendChild(n.stripes);

      n.muzzle = el('ellipse', { cx: 130, cy: 120, rx: 30, ry: 19 });
      body.appendChild(n.muzzle);
      n.cheeks = el('g', { fill: '#FF99A6', opacity: 0.45 });
      n.cheeks.append(el('circle', { cx: 94, cy: 112, r: 8 }), el('circle', { cx: 166, cy: 112, r: 8 }));
      body.appendChild(n.cheeks);

      n.eyeL = this.buildEye(108);
      n.eyeR = this.buildEye(152);
      body.append(n.eyeL.g, n.eyeR.g);

      n.nose = el('path', { d: 'M124,108 L136,108 Q136,116 130,116 Q124,116 124,108 Z', fill: '#F28C99' });
      body.appendChild(n.nose);
      n.mouthNormal = el('path', { d: 'M120,117 Q125,127 130,119 Q135,127 140,117', fill: 'none', 'stroke-width': 1.8, 'stroke-linecap': 'round' });
      n.mouthSad = el('path', { d: 'M120,127 Q130,115 140,127', fill: 'none', 'stroke-width': 1.8, 'stroke-linecap': 'round' });
      n.mouthOpen = el('ellipse', { cx: 130, cy: 124, rx: 4, ry: 4.5, fill: '#8C3340' });
      body.append(n.mouthNormal, n.mouthSad, n.mouthOpen);
      n.whiskers = el('path', {
        d: 'M100,112 L70,106 M100,117 L66,117 M100,122 L70,128 M160,112 L190,106 M160,117 L194,117 M160,122 L190,128',
        fill: 'none', 'stroke-width': 1.5, 'stroke-linecap': 'round',
      });
      body.appendChild(n.whiskers);

      // Аксессуары
      n.bow = el('g', { transform: 'translate(92,80)', fill: '#E64D66' });
      n.bow.append(
        el('ellipse', { cx: -10, cy: 0, rx: 9, ry: 6, transform: 'rotate(-15 -10 0)' }),
        el('ellipse', { cx: 10, cy: 0, rx: 9, ry: 6, transform: 'rotate(15 10 0)' }),
        el('circle', { cx: 0, cy: 0, r: 4, opacity: 0.85 }),
      );
      n.glasses = el('g', { transform: 'translate(130,97)', fill: 'none', stroke: '#33333F', 'stroke-width': 2.5, 'stroke-linecap': 'round' });
      n.glasses.append(
        el('circle', { cx: -22, cy: 0, r: 13 }), el('circle', { cx: 22, cy: 0, r: 13 }),
        el('path', { d: 'M-9,-2 Q0,-8 9,-2' }), el('path', { d: 'M-35,-2 L-46,-6 M35,-2 L46,-6' }),
      );
      n.hat = el('g', { transform: 'translate(130,40)' });
      n.hat.append(
        el('rect', { x: -29, y: -11, width: 58, height: 30, rx: 15, fill: '#D9404D' }),
        el('rect', { x: -31, y: 9, width: 62, height: 10, rx: 5, fill: 'rgba(255,255,255,0.92)' }),
        el('circle', { cx: 0, cy: -14, r: 7, fill: '#FFFFFF' }),
      );
      n.scarf = el('g', { transform: 'translate(130,152)' });
      n.scarf.append(
        el('rect', { x: -46, y: -9, width: 92, height: 18, rx: 9, fill: '#D9404D' }),
        el('rect', { x: 23, y: 3, width: 14, height: 30, rx: 5, fill: '#D9404D' }),
        el('rect', { x: 25, y: 27.5, width: 10, height: 3, rx: 1.5, fill: 'rgba(255,255,255,0.7)' }),
      );
      body.append(n.bow, n.glasses, n.hat, n.scarf);

      // Ноутбук
      n.laptop = el('rect', { x: 38, y: 191, width: 184, height: 34, rx: 6 });
      n.keys = el('g');
      buildKeys(n.keys);
      body.append(n.laptop, n.keys);

      // Картинка в лапках
      n.held = el('g', { transform: 'translate(130,164) rotate(-3)', class: 'held' });
      n.heldFrame = el('rect', { x: -55, y: -39, width: 110, height: 78, rx: 3, fill: '#FFFFFF', filter: 'url(#held-shadow)' });
      n.heldImg = el('image', { x: -52, y: -36, width: 104, height: 72, preserveAspectRatio: 'xMidYMid meet' });
      // Карточка документа: когда котик держит не картинку.
      n.heldDoc = el('g');
      n.heldDoc.append(
        el('rect', { x: -52, y: -36, width: 104, height: 72, fill: '#F4F5F8' }),
        el('path', { d: 'M-18,-28 h22 l12,12 v34 h-34 z', fill: '#FFFFFF', stroke: '#B8BCC6', 'stroke-width': 1.5, 'stroke-linejoin': 'round' }),
        el('path', { d: 'M4,-28 v12 h12', fill: 'none', stroke: '#B8BCC6', 'stroke-width': 1.5, 'stroke-linejoin': 'round' }),
      );
      n.heldExt = el('text', { x: 0, y: 8, 'text-anchor': 'middle', 'font-size': 11, 'font-weight': 700, fill: '#ED8C33', 'font-family': 'system-ui, sans-serif' });
      n.heldName = el('text', { x: 0, y: 30, 'text-anchor': 'middle', 'font-size': 7, fill: '#555', 'font-family': 'system-ui, sans-serif' });
      n.heldDoc.append(n.heldExt, n.heldName);
      // Бейдж «+N», когда котик держит несколько файлов.
      n.heldBadge = el('g', { transform: 'translate(50,-34)' });
      n.heldBadgeText = el('text', { x: 0, y: 3.5, 'text-anchor': 'middle', 'font-size': 9, 'font-weight': 700, fill: '#FFFFFF', 'font-family': 'system-ui, sans-serif' });
      n.heldBadge.append(el('circle', { r: 9, fill: '#ED8C33', stroke: '#FFFFFF', 'stroke-width': 2 }), n.heldBadgeText);
      n.held.append(n.heldFrame, n.heldImg, n.heldDoc, n.heldBadge);
      body.appendChild(n.held);

      // Лапки
      n.pawL = this.buildPaw();
      n.pawR = this.buildPaw();
      body.append(n.pawL.g, n.pawR.g);

      n.food = el('text', { x: 130, y: 151, 'text-anchor': 'middle', 'font-size': 26, class: 'food' });
      n.food.textContent = '🐟';
      body.appendChild(n.food);
      n.hearts = el('g');
      body.appendChild(n.hearts);

      svg.appendChild(body);
      n.bodyGroup = body;

      n.zzz = el('text', { x: 196, y: 47, 'text-anchor': 'middle', 'font-size': 15, 'font-weight': 700, fill: '#8A8A8F', class: 'zzz' });
      n.zzz.textContent = 'z z Z';
      svg.appendChild(n.zzz);

      this.svg = svg;
      this.container.appendChild(svg);

      this.bubble = document.createElement('div');
      this.bubble.className = 'bubble';
      this.bubble.hidden = true;
      this.container.appendChild(this.bubble);
    }

    buildEye(cx) {
      const g = el('g', { transform: `translate(${cx},96)` });
      const normal = el('g');
      const pupil = el('ellipse', { cx: 0, cy: 0, rx: 7, ry: 9 });
      const shine = el('circle', { cx: 3, cy: -4, r: 2.5, fill: '#FFFFFF' });
      normal.append(pupil, shine);
      const lid = el('rect', { x: -9, y: -16, width: 18, height: 9 });
      const happy = el('path', { d: 'M-8,4 Q0,-9 8,4', fill: 'none', 'stroke-width': 3, 'stroke-linecap': 'round' });
      const closed = el('rect', { x: -8, y: -1.5, width: 16, height: 3, rx: 1.5 });
      g.append(normal, lid, happy, closed);
      return { g, normal, pupil, lid, happy, closed };
    }

    buildPaw() {
      const g = el('g', { class: 'paw' });
      const pad = el('rect', { x: -23, y: -15, width: 46, height: 30, rx: 13, 'stroke-width': 1 });
      const toes = el('g', { class: 'toes' });
      for (const x of [-9, -1, 7]) toes.appendChild(el('rect', { x, y: -12.5, width: 2, height: 9, rx: 1 }));
      g.append(pad, toes);
      return { g, pad, toes };
    }

    // MARK: - Настройки внешности

    applySettings(s) {
      Object.assign(this.settings, s);
      const n = this.n;
      const fur = FURS[this.settings.fur] || FURS.ginger;
      const eye = (EYES[this.settings.eyeColor] || EYES.auto).color || fur.eye;
      const kb = KEYBOARDS[this.settings.keyboard] || KEYBOARDS.dark;
      this.palette = { fur, eye, kb };

      n.tail.setAttribute('stroke', fur.fur);
      n.body.setAttribute('fill', fur.fur);
      n.head.setAttribute('fill', fur.fur);
      n.earLOuter.setAttribute('fill', fur.fur);
      n.earROuter.setAttribute('fill', fur.fur);
      n.belly.setAttribute('fill', fur.belly);
      n.muzzle.setAttribute('fill', fur.belly);
      n.stripes.style.display = fur.stripe ? '' : 'none';
      if (fur.stripe) n.stripes.setAttribute('fill', fur.stripe);
      for (const eyeNode of [n.eyeL, n.eyeR]) {
        eyeNode.pupil.setAttribute('fill', eye);
        eyeNode.happy.setAttribute('stroke', eye);
        eyeNode.closed.setAttribute('fill', eye);
        eyeNode.lid.setAttribute('fill', fur.fur);
      }
      n.mouthNormal.setAttribute('stroke', fur.outline);
      n.mouthSad.setAttribute('stroke', fur.outline);
      n.whiskers.setAttribute('stroke', fur.outline);
      n.laptop.setAttribute('fill', kb.base);
      n.keys.setAttribute('fill', kb.keys);
      for (const paw of [n.pawL, n.pawR]) {
        paw.pad.setAttribute('fill', fur.belly);
        paw.pad.setAttribute('stroke', fur.outline);
        paw.pad.setAttribute('stroke-opacity', 0.35);
        paw.toes.setAttribute('fill', fur.outline);
        paw.toes.setAttribute('fill-opacity', 0.25);
      }
      const acc = this.settings.accessory;
      n.bow.style.display = acc === 'bow' ? '' : 'none';
      n.glasses.style.display = acc === 'glasses' ? '' : 'none';
      n.hat.style.display = acc === 'hat' ? '' : 'none';
      n.scarf.style.display = acc === 'scarf' ? '' : 'none';
      n.bodyGroup.setAttribute('transform', this.settings.mirrored ? 'translate(260,0) scale(-1,1)' : '');
      this.svg.style.opacity = this.options.fixedOpacity ? 1 : (this.settings.opacity ?? 1);
      this.render();
    }

    // MARK: - Поведение

    tap(paw) {
      const s = this.state;
      s.lastActivity = Date.now();
      s.happiness = Math.min(1, s.happiness + 0.001);
      s.tapsSinceBubble += 1;
      const key = paw === 'left' ? 'leftDown' : 'rightDown';
      s[key] = true;
      clearTimeout(this.timers[paw]);
      this.timers[paw] = setTimeout(() => { s[key] = false; this.renderPaws(); }, 100);
      this.renderPaws();
    }

    pet() {
      const s = this.state;
      s.lastActivity = Date.now();
      s.happiness = Math.min(1, s.happiness + 0.08);
      s.petBoostUntil = Date.now() + 2500;
      this.setMood('happy');
      this.say(pick(['мурр', 'ещё!', 'вот тут, да', '❤️', 'мр-р-р']));
      this.spawnHeart();
    }

    feed() {
      const s = this.state;
      if (s.eating) return;
      s.lastActivity = Date.now();
      s.happiness = Math.min(1, s.happiness + 0.25);
      s.eating = true;
      this.say(pick(['ням-ням', 'рыбка!', 'спасибо 🐟', 'ом-ном-ном']));
      this.render();
      setTimeout(() => { s.eating = false; s.petBoostUntil = Date.now() + 3000; this.render(); }, 2200);
    }

    /// dataUrl — миниатюра картинки; для документа null и имя файла в meta.name.
    /// meta.count — сколько всего файлов в стопке (бейдж при >1).
    hold(dataUrl, meta = {}) {
      this.state.held = dataUrl || meta.name || 'doc';
      this.state.lastActivity = Date.now();
      const count = meta.count || 1;
      this.n.heldBadge.style.display = count > 1 ? '' : 'none';
      this.n.heldBadgeText.textContent = count > 99 ? '99+' : String(count);
      if (dataUrl) {
        this.n.heldImg.setAttribute('href', dataUrl);
        this.n.heldImg.style.display = '';
        this.n.heldDoc.style.display = 'none';
      } else {
        const name = meta.name || '';
        const ext = (name.includes('.') ? name.split('.').pop() : '').slice(0, 5).toUpperCase() || 'ФАЙЛ';
        const base = name.replace(/^cat-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-/, '');
        this.n.heldExt.textContent = ext;
        this.n.heldName.textContent = base.length > 22 ? `${base.slice(0, 20)}…` : base;
        this.n.heldImg.removeAttribute('href');
        this.n.heldImg.style.display = 'none';
        this.n.heldDoc.style.display = '';
      }
      this.render();
    }

    putAway() {
      this.state.held = null;
      this.n.heldImg.removeAttribute('href');
      this.render();
    }

    say(text, seconds = 2.6) {
      if (!this.settings.bubbles || !text) return;
      clearTimeout(this.timers.bubble);
      this.bubble.textContent = text;
      this.bubble.hidden = false;
      this.bubble.classList.remove('bubble-in');
      void this.bubble.offsetWidth;
      this.bubble.classList.add('bubble-in');
      this.timers.bubble = setTimeout(() => { this.bubble.hidden = true; }, seconds * 1000);
    }

    tick(cpm = 0) {
      const s = this.state;
      const now = Date.now();
      s.happiness = Math.max(0, s.happiness - 0.0003);
      const idle = (now - s.lastActivity) / 1000;
      let mood;
      if (s.eating || now < s.petBoostUntil) mood = 'happy';
      else if (idle > 120) mood = 'sleepy';
      else if (cpm >= 220) mood = 'excited';
      else if (s.happiness > 0.8) mood = 'happy';
      else if (s.happiness < 0.2) mood = 'grumpy';
      else mood = 'normal';
      this.setMood(mood);

      if (this.bubble.hidden && idle < 20 && now - s.lastRandomBubble > 45000 && s.tapsSinceBubble > 60) {
        s.lastRandomBubble = now;
        s.tapsSinceBubble = 0;
        if (Math.random() < 0.34) this.say(pick(cpm >= 220 ? FAST_PHRASES : IDLE_PHRASES));
      }
    }

    setMood(mood) {
      if (this.state.mood === mood) return;
      this.state.mood = mood;
      this.render();
      if (this.onMoodChange) this.onMoodChange(mood, MOODS[mood]);
    }

    scheduleBlink() {
      const delay = 2500 + Math.random() * 3500;
      setTimeout(() => {
        if (this.state.mood !== 'sleepy') {
          this.state.blinking = true;
          this.renderEyes();
          setTimeout(() => { this.state.blinking = false; this.renderEyes(); }, 120);
        }
        this.scheduleBlink();
      }, delay);
    }

    spawnHeart() {
      const x = 95 + Math.random() * 70;
      const heart = el('text', { x, y: 70, 'text-anchor': 'middle', 'font-size': 16, class: 'heart' });
      heart.textContent = '❤️';
      this.n.hearts.appendChild(heart);
      setTimeout(() => heart.remove(), 1300);
    }

    // MARK: - Отрисовка

    render() {
      this.renderEyes();
      this.renderPaws();
      const n = this.n;
      const s = this.state;
      const happy = s.mood === 'happy' || s.eating;
      n.cheeks.style.display = happy ? '' : 'none';
      const open = s.eating || s.mood === 'excited';
      n.mouthOpen.style.display = open ? '' : 'none';
      n.mouthSad.style.display = !open && s.mood === 'grumpy' ? '' : 'none';
      n.mouthNormal.style.display = !open && s.mood !== 'grumpy' ? '' : 'none';
      n.tail.classList.toggle('wag', s.mood === 'happy' || s.mood === 'excited');
      n.food.style.display = s.eating ? '' : 'none';
      n.zzz.style.display = s.mood === 'sleepy' ? '' : 'none';
      n.held.style.display = s.held ? '' : 'none';
    }

    renderEyes() {
      const s = this.state;
      for (const eye of [this.n.eyeL, this.n.eyeR]) {
        const closed = s.blinking || s.mood === 'sleepy';
        const happy = !closed && s.mood === 'happy';
        const normal = !closed && !happy;
        eye.closed.style.display = closed ? '' : 'none';
        eye.happy.style.display = happy ? '' : 'none';
        eye.normal.style.display = normal ? '' : 'none';
        eye.lid.style.display = normal && s.mood === 'grumpy' ? '' : 'none';
        eye.pupil.setAttribute('ry', s.mood === 'excited' ? 10.5 : 9);
      }
    }

    renderPaws() {
      const s = this.state;
      const holding = !!s.held;
      const place = (paw, side, down) => {
        let x, y, rot;
        if (holding) { x = side === 'left' ? 76 : 184; y = down ? 171 : 168; rot = side === 'left' ? -25 : 25; }
        else { x = side === 'left' ? 86 : 174; y = down ? 196 : 184; rot = down ? (side === 'left' ? -6 : 6) : 0; }
        paw.g.setAttribute('transform', `translate(${x},${y}) rotate(${rot})`);
      };
      // В зеркале лапы меняются местами, чтобы левая клавиша била ближней лапой.
      const leftDown = this.settings.mirrored ? s.rightDown : s.leftDown;
      const rightDown = this.settings.mirrored ? s.leftDown : s.rightDown;
      place(this.n.pawL, 'left', leftDown);
      place(this.n.pawR, 'right', rightDown);
    }

    /// Попадает ли точка (в CSS-пикселях контейнера) в картинку в лапках.
    hitHeld(clientX, clientY) {
      if (!this.state.held) return false;
      const rect = this.svg.getBoundingClientRect();
      const k = rect.width / 260;
      const x = (clientX - rect.left) / k;
      const y = (clientY - rect.top) / k;
      return x >= HELD_RECT.x && x <= HELD_RECT.x + HELD_RECT.width && y >= HELD_RECT.y && y <= HELD_RECT.y + HELD_RECT.height;
    }
  }

  window.CatRenderer = CatRenderer;
  window.CatCatalog = { FURS, EYES, KEYBOARDS, ACCESSORIES, SIZES, MOODS };
})();
