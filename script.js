document.addEventListener("DOMContentLoaded", () => {
  const header = document.querySelector(".site-header");
  const mainNav = document.querySelector(".main-nav");
  const menuToggle = document.querySelector(".menu-toggle");

  const getHeaderHeight = () => (header ? header.offsetHeight : 0);
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

  // Mobile nav toggle
  if (menuToggle && mainNav) {
    menuToggle.addEventListener("click", () => {
      mainNav.classList.toggle("open");
    });
  }

  // Smooth scroll with dynamic header offset
  document.querySelectorAll('a[href^="#"]').forEach((link) => {
    link.addEventListener("click", (event) => {
      const targetId = link.getAttribute("href");
      if (!targetId || targetId === "#") return;

      const target = document.querySelector(targetId);
      if (!target) return;

      event.preventDefault();

      const headerHeight = getHeaderHeight();
      const rect = target.getBoundingClientRect();
      const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      const offset = rect.top + scrollTop - headerHeight + 4;

      window.scrollTo({
        top: offset,
        behavior: "smooth"
      });

      // Close mobile menu after navigation
      if (mainNav) mainNav.classList.remove("open");
    });
  });

  // Hero carousel
  const heroCarousel = document.querySelector(".hero-carousel");
  const slides = Array.from(document.querySelectorAll(".hero-slide"));
  const dots = Array.from(document.querySelectorAll(".hero-dot"));
  let current = 0;
  let heroTimer = null;

  function setSlide(index, options = {}) {
    if (!slides.length) return;
    const total = slides.length;
    const next = ((index % total) + total) % total;
    const shouldFocusDot = Boolean(options.focusDot);

    slides.forEach((slide, i) => {
      const isActive = i === next;
      slide.classList.toggle("active", isActive);
      slide.setAttribute("aria-hidden", String(!isActive));
    });

    dots.forEach((dot, i) => {
      const isActive = i === next;
      dot.classList.toggle("active", isActive);
      dot.setAttribute("aria-selected", String(isActive));
      dot.tabIndex = isActive ? 0 : -1;
      if (isActive && shouldFocusDot) dot.focus();
    });

    current = next;
  }

  function startHeroTimer() {
    if (!slides.length) return;
    if (heroTimer) window.clearInterval(heroTimer);
    heroTimer = window.setInterval(() => {
      setSlide(current + 1);
    }, 8000);
  }

  if (slides.length && dots.length) {
    const moveBy = (delta, focusDot = false) => {
      setSlide(current + delta, { focusDot });
      startHeroTimer();
    };

    dots.forEach((dot) => {
      dot.addEventListener("click", () => {
        const idx = parseInt(dot.dataset.index || "0", 10);
        setSlide(idx);
        startHeroTimer();
      });

      dot.addEventListener("keydown", (event) => {
        if (event.key === "ArrowRight" || event.key === "ArrowDown") {
          event.preventDefault();
          moveBy(1, true);
        }

        if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
          event.preventDefault();
          moveBy(-1, true);
        }

        if (event.key === "Home") {
          event.preventDefault();
          setSlide(0, { focusDot: true });
          startHeroTimer();
        }

        if (event.key === "End") {
          event.preventDefault();
          setSlide(slides.length - 1, { focusDot: true });
          startHeroTimer();
        }
      });
    });

    if (heroCarousel) {
      heroCarousel.addEventListener("mouseenter", () => {
        if (heroTimer) window.clearInterval(heroTimer);
      });

      heroCarousel.addEventListener("mouseleave", () => {
        startHeroTimer();
      });

      heroCarousel.addEventListener("focusin", () => {
        if (heroTimer) window.clearInterval(heroTimer);
      });

      heroCarousel.addEventListener("focusout", (event) => {
        if (!heroCarousel.contains(event.relatedTarget)) startHeroTimer();
      });
    }

    setSlide(0);
    startHeroTimer();
  }

  // Active nav highlighting (adds .is-active to the current section link)
  const navLinks = Array.from(document.querySelectorAll(".nav-links a[href^='#']"));
  const navTargets = navLinks
    .map((link) => {
      const id = link.getAttribute("href");
      const target = id ? document.querySelector(id) : null;
      return target ? { link, target, id } : null;
    })
    .filter(Boolean);

  const updateActiveNav = () => {
    if (!navTargets.length) return;

    const marker = getHeaderHeight() + 90;
    let active = navTargets[0];

    for (const item of navTargets) {
      const rect = item.target.getBoundingClientRect();
      if (rect.top <= marker) active = item;
    }

    navTargets.forEach((item) => {
      item.link.classList.toggle("is-active", item === active);
    });
  };

  // Parallax (subtle, performance-friendly, respects reduced motion)
  const reduceMotionMq = window.matchMedia("(prefers-reduced-motion: reduce)");
  const parallaxItems = Array.from(document.querySelectorAll(".hero-media, .immersive-media")).map((el) => {
    const isHero = el.classList.contains("hero-media");
    return {
      el,
      max: isHero ? 48 : 34
    };
  });

  const resetParallax = () => {
    parallaxItems.forEach(({ el }) => {
      el.style.setProperty("--parallax-y", "0px");
    });
  };

  const updateParallax = () => {
    if (reduceMotionMq.matches || !parallaxItems.length) return;

    const viewportCenter = (window.innerHeight || 0) / 2;

    parallaxItems.forEach(({ el, max }) => {
      const rect = el.getBoundingClientRect();
      // Skip if far off-screen to avoid unnecessary work
      if (rect.bottom < -200 || rect.top > (window.innerHeight || 0) + 200) return;

      const center = rect.top + rect.height / 2;
      const delta = clamp((center - viewportCenter) / viewportCenter, -1, 1);

      // Move slowly in the opposite direction of scroll for depth
      const translate = clamp(-delta * max, -max, max);
      el.style.setProperty("--parallax-y", `${translate.toFixed(2)}px`);
    });
  };

  // Stacked hero transition (Manufacturing -> R&D slide-over)
  const stackSection = document.querySelector(".stack-section");
  let syncStackHeight = null;
  let updateStackAnimation = null;

  if (stackSection) {
    const panels = Array.from(stackSection.querySelectorAll(".stack-panel"));
    const rndPanel = stackSection.querySelector(".rnd-hero");
    const secondAnchor = stackSection.querySelector(".stack-anchor--second");

    syncStackHeight = () => {
      const headerHeightNow = getHeaderHeight();
      const stageHeight = Math.max(0, (window.innerHeight || 0) - headerHeightNow);
      const panelCount = Math.max(1, panels.length);

      // Scroll distance is panelCount * stageHeight; pinned distance is (panelCount - 1) * stageHeight
      stackSection.style.height = `${stageHeight * panelCount}px`;

      // Keep the second anchor exactly one stage-height into the section
      if (secondAnchor) secondAnchor.style.top = `${stageHeight}px`;

      if (updateStackAnimation) updateStackAnimation();
    };

    updateStackAnimation = () => {
      if (!rndPanel) return;

      const headerHeightNow = getHeaderHeight();
      const stageHeight = Math.max(0, (window.innerHeight || 0) - headerHeightNow);
      const rect = stackSection.getBoundingClientRect();
      const total = Math.max(1, stackSection.offsetHeight - stageHeight);

      // 0 when section top reaches the sticky top; 1 when we scroll through the pinned distance.
      const progress = clamp((headerHeightNow - rect.top) / total, 0, 1);

      // Slide the R&D panel over the Manufacturing panel, fully covering it
      rndPanel.style.transform = `translateY(${(1 - progress) * 100}%)`;
    };

    // Initial sizing
    syncStackHeight();
  }

  // One rAF-driven scroll loop for smoothness
  let ticking = false;

  const onFrame = () => {
    ticking = false;

    if (updateStackAnimation) updateStackAnimation();
    updateActiveNav();
    updateParallax();
  };

  const requestFrame = () => {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(onFrame);
  };

  window.addEventListener("scroll", requestFrame, { passive: true });
  window.addEventListener(
    "resize",
    () => {
      if (syncStackHeight) syncStackHeight();
      requestFrame();
    },
    { passive: true }
  );

  if (typeof reduceMotionMq.addEventListener === "function") {
    reduceMotionMq.addEventListener("change", () => {
      if (reduceMotionMq.matches) resetParallax();
      requestFrame();
    });
  }

  // Initial paint
  requestFrame();
});