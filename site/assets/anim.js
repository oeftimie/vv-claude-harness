/* Animations for the harness teaching site.
 *
 * anime.js v4.5.0 (MIT), pinned ES module. Every scene here carries an idea from the
 * page it sits on; nothing animates purely for decoration.
 *
 * Contract each scene follows:
 *   still(root)  - put the scene in its finished state, no motion (reduced motion, or
 *                  as the base state before setup runs)
 *   setup(root)  - move the scene to its starting state (optional)
 *   play(root)   - build and return the animation/timeline
 *
 * Scenes are found by [data-scene="<name>"] and skipped silently when absent, so every
 * page imports this one module.
 */

import {
  animate,
  createTimeline,
  stagger,
  onScroll,
  svg,
  utils,
} from 'https://cdn.jsdelivr.net/npm/animejs@4.5.0/dist/bundles/anime.esm.min.js';

const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const all = (root, sel) => Array.from(root.querySelectorAll(sel));
const show = (root, sel) => utils.set(all(root, sel), { opacity: 1 });

/* Scroll trigger: play once when the figure comes into view. ScrollObserver's `repeat`
   defaults to true, so playing once is an explicit repeat: false. */
const onEnterView = (root) => onScroll({ target: root, repeat: false });

const scenes = {};

/* ---------------------------------------------------------------- A1 hero ------- */

scenes.hero = {
  still(root) {
    utils.set(all(root, '.hero-word, .hero-fade, .stat'), { opacity: 1, translateY: 0 });
  },
  setup(root) {
    utils.set(all(root, '.hero-word'), { opacity: 0, translateY: '0.5em' });
    utils.set(all(root, '.hero-fade'), { opacity: 0, translateY: 10 });
    utils.set(all(root, '.stat'), { opacity: 0, translateY: 12 });
  },
  play(root) {
    return createTimeline()
      .add(all(root, '.hero-word'), {
        opacity: 1,
        translateY: 0,
        duration: 750,
        ease: 'outExpo',
        delay: stagger(55),
      })
      .add(all(root, '.hero-fade'), {
        opacity: 1,
        translateY: 0,
        duration: 600,
        ease: 'outQuad',
        delay: stagger(90),
      }, '-=350')
      .add(all(root, '.stat'), {
        opacity: 1,
        translateY: 0,
        duration: 500,
        ease: 'outBack',
        delay: stagger(70),
      }, '-=250');
  },
};

/* --------------------------------------------------- A2 the session boundary ---- */
/* Left column loses its memory at the boundary; the right column writes it to a file
   first and starts the next session pre-filled. This is the whole argument for the
   harness, so it is the one scene that runs on both columns at once for comparison. */

scenes.shift = {
  still(root) {
    utils.set(all(root, '.mem'), { height: 44, opacity: 1 });
    utils.set(all(root, '[data-kind="none"] [data-band="2"] .mem'), { height: 6, opacity: 0.35 });
    show(root, '.persist, .lost');
  },
  setup(root) {
    utils.set(all(root, '.mem'), { height: 6, opacity: 1 });
    utils.set(all(root, '.persist, .lost'), { opacity: 0 });
  },
  play(root) {
    const band = (kind, n) => all(root, `[data-kind="${kind}"] [data-band="${n}"] .mem`);
    const tl = createTimeline({ autoplay: onEnterView(root) });

    // Session 1 — both sides accumulate the same knowledge.
    tl.add([...band('none', 1), ...band('harness', 1)], {
      height: 44,
      duration: 700,
      ease: 'outElastic',
      delay: stagger(90),
    });

    // The boundary. Left drains; right is written down first.
    tl.add(root.querySelector('[data-kind="harness"] .persist'), {
      opacity: 1,
      translateY: [6, 0],
      duration: 400,
      ease: 'outQuad',
    }, '+=250');

    tl.add(band('none', 1), {
      height: 6,
      opacity: 0.35,
      duration: 600,
      ease: 'inQuad',
      delay: stagger(50),
    }, '<<');

    tl.add(root.querySelector('[data-kind="none"] .lost'), {
      opacity: 1,
      duration: 400,
    }, '-=200');

    // Session 2 — only the right side starts where session 1 ended.
    tl.add(band('harness', 2), {
      height: 44,
      duration: 550,
      ease: 'outExpo',
      delay: stagger(70),
    }, '+=200');

    return tl;
  },
};

/* ------------------------------------------------------- A3 / A11 file trees ---- */

scenes.tree = {
  still(root) {
    utils.set(all(root, '.row'), { opacity: 1, translateX: 0 });
  },
  setup(root) {
    utils.set(all(root, '.row'), { opacity: 0, translateX: -10 });
  },
  play(root) {
    return animate(all(root, '.row'), {
      opacity: 1,
      translateX: 0,
      duration: 380,
      ease: 'outQuad',
      delay: stagger(35),
      autoplay: onEnterView(root),
    });
  },
};

/* ------------------------------------------------------- A11 terminal typing ---- */

scenes.term = {
  still(root) {
    utils.set(all(root, '.line'), { opacity: 1 });
  },
  setup(root) {
    utils.set(all(root, '.line'), { opacity: 0 });
  },
  play(root) {
    return animate(all(root, '.line'), {
      opacity: 1,
      translateY: [4, 0],
      duration: 260,
      ease: 'outQuad',
      delay: stagger(160),
      autoplay: onEnterView(root),
    });
  },
};

/* ------------------------------------------------------------ A4 session loop --- */
/* A marker travels a closed path: the loop is a cycle you re-enter every session,
   not a checklist you finish once. */

scenes.loop = {
  still(root) {
    const steps = all(root, '.loop-steps li');
    steps.forEach((li) => li.classList.add('on'));
    utils.set(root.querySelector('.marker'), { opacity: 1 });
  },
  setup(root) {
    all(root, '.loop-steps li').forEach((li) => li.classList.remove('on'));
    utils.set(root.querySelector('.marker'), { opacity: 1 });
  },
  play(root) {
    const path = root.querySelector('#loop-path');
    const marker = root.querySelector('.marker');
    const steps = all(root, '.loop-steps li');
    const motion = svg.createMotionPath(path);

    return animate(marker, {
      translateX: motion.translateX,
      translateY: motion.translateY,
      duration: 9000,
      ease: 'linear',
      loop: true,
      autoplay: onEnterView(root),
      onUpdate: (self) => {
        // iterationProgress, not progress: on a looping animation `progress` is measured
        // against an infinite total duration and never leaves 0.
        const i = Math.min(steps.length - 1, Math.floor(self.iterationProgress * steps.length));
        steps.forEach((li, n) => li.classList.toggle('on', n === i));
      },
    });
  },
};

/* -------------------------------------------------------------- A5 compaction --- */

scenes.compact = {
  still(root) {
    utils.set(root.querySelector('.ctx-fill'), { width: '22%' });
    show(root, '.reinject .chip');
  },
  setup(root) {
    utils.set(root.querySelector('.ctx-fill'), { width: '4%' });
    utils.set(all(root, '.reinject .chip'), { opacity: 0 });
  },
  play(root) {
    const fill = root.querySelector('.ctx-fill');
    return createTimeline({ autoplay: onEnterView(root) })
      .add(fill, {
        width: ['4%', '94%'],
        backgroundColor: ['#2a5a8a', '#b8482a'],
        duration: 2600,
        ease: 'inOutQuad',
      })
      .add(fill, {
        width: '22%',
        backgroundColor: '#2f6b46',
        duration: 500,
        ease: 'outExpo',
      }, '+=350')
      .add(all(root, '.reinject .chip'), {
        opacity: 1,
        translateY: [8, 0],
        duration: 400,
        ease: 'outBack',
        delay: stagger(110),
      }, '-=150');
  },
};

/* ----------------------------------------------------------------- A6 the gate -- */
/* A gate does not advise: it returns a non-zero exit code and the action does not
   happen. The token bounces, then passes only once the check is green. */

scenes.gate = {
  still(root) {
    utils.set(root.querySelector('.token'), { left: '84%' });
    utils.set(root.querySelector('.gate-bar'), { backgroundColor: '#2f6b46' });
    root.querySelector('.gate-label').textContent = 'tests pass → allowed';
  },
  setup(root) {
    utils.set(root.querySelector('.token'), { left: '14%' });
    utils.set(root.querySelector('.gate-bar'), { backgroundColor: '#cbc8bd' });
  },
  play(root) {
    const commit = root.querySelector('.token');
    const bar = root.querySelector('.gate-bar');
    const label = root.querySelector('.gate-label');

    return createTimeline({ autoplay: onEnterView(root) })
      .call(() => { label.textContent = 'commit-gate.sh'; })
      .add(commit, { left: '44%', duration: 900, ease: 'outQuad' })
      .add(bar, { backgroundColor: '#b8482a', scaleX: 2.2, duration: 180 })
      .call(() => { label.textContent = 'exit 2 — suite red, denied'; })
      .add(commit, { left: '20%', duration: 700, ease: 'outBack' })
      .add(bar, { scaleX: 1, duration: 300 }, '<<')
      .call(() => { label.textContent = 'suite green'; })
      .add(bar, { backgroundColor: '#2f6b46', duration: 400 }, '+=500')
      .add(commit, { left: '84%', duration: 1100, ease: 'inOutQuad' })
      .call(() => { label.textContent = 'tests pass → allowed'; });
  },
};

/* ------------------------------------------------------------ A7 the four tiers - */

scenes.tiers = {
  still(root) {
    all(root, '.tier').forEach((t) => {
      t.querySelector('.bar').style.width = `${t.dataset.pct}%`;
    });
  },
  setup(root) {
    utils.set(all(root, '.tier .bar'), { width: '0%' });
  },
  play(root) {
    const tl = createTimeline({ autoplay: onEnterView(root) });
    all(root, '.tier').forEach((t, i) => {
      tl.add(t.querySelector('.bar'), {
        width: `${t.dataset.pct}%`,
        duration: 900,
        ease: 'outExpo',
      }, i === 0 ? 0 : '-=700');
    });
    return tl;
  },
};

/* ---------------------------------------------------------- A8 the task gate ---- */

scenes.lanes = {
  still(root) {
    show(root, '.lane .mark');
  },
  setup(root) {
    utils.set(all(root, '.lane .mark'), { opacity: 0 });
  },
  play(root) {
    return animate(all(root, '.lane .mark'), {
      opacity: 1,
      scale: [0.5, 1],
      duration: 380,
      ease: 'outBack',
      delay: stagger(650),
      autoplay: onEnterView(root),
    });
  },
};

/* ------------------------------------------------------------- A9 fan out ------- */
/* Lead fans out to isolated worktrees, each running implementer → reviewer, then the
   branches converge back for the lead to integrate. */

scenes.fan = {
  still(root) {
    show(root, '.node.worker');
    utils.set(all(root, '.fan path'), { strokeDashoffset: 0 });
  },
  setup(root) {
    // Opacity only, never a transform: .node is centred on its anchor point with a CSS
    // translate(-50%, -50%), and anime writes the whole transform property at once.
    utils.set(all(root, '.node.worker'), { opacity: 0 });
    all(root, '.fan path').forEach((p) => {
      const len = p.getTotalLength();
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
    });
  },
  play(root) {
    return createTimeline({ autoplay: onEnterView(root) })
      .add(all(root, '.fan path'), {
        strokeDashoffset: 0,
        duration: 800,
        ease: 'outQuad',
        delay: stagger(120, { from: 'center' }),
      })
      .add(all(root, '.node.worker'), {
        opacity: 1,
        duration: 500,
        ease: 'outQuad',
        delay: stagger(110, { from: 'center' }),
      }, '-=450');
  },
};

/* ------------------------------------------------ A10 independence = no overlap - */

scenes.scopes = {
  still(root) {
    const [a, b] = all(root, '.scope-box');
    utils.set(a, { left: '4%', width: '44%' });
    utils.set(b, { left: '52%', width: '44%' });
    utils.set([a, b], { borderColor: '#2f6b46' });
    root.querySelector('.verdict').textContent = 'non-overlapping scope + empty depends_on → may run in parallel';
  },
  setup(root) {
    const [a, b] = all(root, '.scope-box');
    utils.set(a, { left: '4%', width: '52%' });
    utils.set(b, { left: '44%', width: '52%' });
  },
  play(root) {
    const [a, b] = all(root, '.scope-box');
    const verdict = root.querySelector('.verdict');

    return createTimeline({ autoplay: onEnterView(root) })
      .call(() => { verdict.textContent = 'scope overlaps — two agents own the same files'; })
      .add([a, b], { borderColor: '#b8482a', duration: 300 }, 600)
      .add(a, { translateX: [0, -6, 6, 0], duration: 300, ease: 'inOutSine' }, '<<')
      .add(b, { translateX: [0, 6, -6, 0], duration: 300, ease: 'inOutSine' }, '<<')
      .call(() => { verdict.textContent = 'sequence them, or split the scope'; })
      .add(a, { width: '44%', duration: 800, ease: 'outExpo' }, '+=400')
      .add(b, { left: '52%', width: '44%', duration: 800, ease: 'outExpo' }, '<<')
      .add([a, b], { borderColor: '#2f6b46', duration: 400 }, '-=300')
      .call(() => {
        verdict.textContent = 'non-overlapping scope + empty depends_on → may run in parallel';
      });
  },
};

/* ------------------------------------------------------- A12 scroll progress ---- */

function progressBar() {
  const bar = document.getElementById('progress');
  if (!bar) return;
  if (reduced) {
    utils.set(bar, { scaleX: 1, opacity: 0.25 });
    return;
  }
  animate(bar, {
    scaleX: [0, 1],
    ease: 'linear',
    autoplay: onScroll({
      target: document.documentElement,
      enter: 'top top',
      leave: 'bottom bottom',
      sync: true,
    }),
  });
}

/* ------------------------------------------------------------------ bootstrap --- */

function init() {
  progressBar();

  document.querySelectorAll('[data-scene]').forEach((root) => {
    const scene = scenes[root.dataset.scene];
    if (!scene) return;

    if (reduced) {
      scene.still(root);
      return;
    }

    scene.setup?.(root);
    const instance = scene.play(root);

    const replay = root.querySelector('.replay');
    replay?.addEventListener('click', () => instance.restart());
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
