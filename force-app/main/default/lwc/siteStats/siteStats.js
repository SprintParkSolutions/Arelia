import { LightningElement, api } from 'lwc';

export default class SiteStats extends LightningElement {
  // default stats; consumer can override by setting the @api stats property
 @api stats = [
    {
      key: 'projects',
      label: 'Bespoke Interiors Delivered',
      value: 180,
      note: 'From compact studios to expansive villas across metros.'
    },
    {
      key: 'clients',
      label: 'Delighted Clients',
      value: 95,
      note: 'Homeowners, founders and corporates who trust our process.'
    },
    {
      key: 'cities',
      label: 'Cities & Towns',
      value: 12,
      note: 'Projects executed beyond a single geography.'
    },
    {
      key: 'years',
      label: 'Years in Craft',
      value: 9,
      note: 'Designing, iterating and refining every single year.'
    }
  ];

  hasObserved = false;

  get primaryStat() {
    return this.stats && this.stats.length ? this._withAria(this.stats[0]) : null;
  }

  get primaryStatAria() {
    const p = this.primaryStat;
    if (!p) return null;
    return `${p.value} ${p.label}`;
  }

  get secondaryStats() {
    if (!this.stats || this.stats.length < 2) return [];
    return this.stats.slice(1, 4).map((s) => this._withAria(s));
  }

  _withAria(stat) {
    return {
      ...stat,
      aria: `${stat.value} ${stat.label}`
    };
  }

  renderedCallback() {
    if (this.hasObserved) return;
    this.hasObserved = true;

    const root = this.template.querySelector('.stats-root');
    if (!root) return;

    const io = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            root.classList.add('in-view');
            this.startCountUp();
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.18 }
    );

    io.observe(root);
  }

  startCountUp() {
    // Respect reduced motion
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      this._setInstantValues();
      return;
    }

    const numbers = this.template.querySelectorAll('.hero-number, .stat-number');
    numbers.forEach((el, index) => {
      const value = parseInt(el.dataset.value, 10) || 0;
      const baseDuration = 1300;
      const extra = index * 120;
      this._animateValue(el, value, baseDuration + extra);
    });
  }

  _setInstantValues() {
    const numbers = this.template.querySelectorAll('.hero-number, .stat-number');
    numbers.forEach((el) => {
      const value = parseInt(el.dataset.value, 10) || 0;
      el.textContent = `${value}+`;
    });
  }

  _animateValue(el, endValue, duration) {
    const startValue = 0;
    const startTime = performance.now();

    const step = (now) => {
      const progress = Math.min((now - startTime) / duration, 1);
      // easeOutCubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.floor(startValue + (endValue - startValue) * eased);
      el.textContent = `${current}+`;

      if (progress < 1) {
        requestAnimationFrame(step);
      } else {
        el.textContent = `${endValue}+`;
      }
    };

    requestAnimationFrame(step);
  }
}