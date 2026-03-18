import { LightningElement, api } from 'lwc';

// --------- Replace these imports with your real commercial image static resource names ---------
import COMM_LOBBY_1 from '@salesforce/resourceUrl/COMM_LOBBY_1';
import COMM_LOBBY_2 from '@salesforce/resourceUrl/COMM_LOBBY_2';
import COMM_LOBBY_3 from '@salesforce/resourceUrl/COMM_LOBBY_3';
import COMM_LOBBY_4 from '@salesforce/resourceUrl/COMM_LOBBY_4';

import COMM_OFFICE_1 from '@salesforce/resourceUrl/COMM_OFFICE_1';
import COMM_OFFICE_2 from '@salesforce/resourceUrl/COMM_OFFICE_2';
import COMM_OFFICE_3 from '@salesforce/resourceUrl/COMM_OFFICE_3';
import COMM_OFFICE_4 from '@salesforce/resourceUrl/COMM_OFFICE_4';

import COMM_CONF_1 from '@salesforce/resourceUrl/COMM_CONF_1';
import COMM_CONF_2 from '@salesforce/resourceUrl/COMM_CONF_2';
import COMM_CONF_3 from '@salesforce/resourceUrl/COMM_CONF_3';
import COMM_CONF_4 from '@salesforce/resourceUrl/COMM_CONF_4';

import COMM_RETAIL_1 from '@salesforce/resourceUrl/COMM_RETAIL_1';
import COMM_RETAIL_2 from '@salesforce/resourceUrl/COMM_RETAIL_2';
import COMM_RETAIL_3 from '@salesforce/resourceUrl/COMM_RETAIL_3';
import COMM_RETAIL_4 from '@salesforce/resourceUrl/COMM_RETAIL_4';

import COMM_FNB_1 from '@salesforce/resourceUrl/COMM_FNB_1';
import COMM_FNB_2 from '@salesforce/resourceUrl/COMM_FNB_2';
import COMM_FNB_3 from '@salesforce/resourceUrl/COMM_FNB_3';
import COMM_FNB_4 from '@salesforce/resourceUrl/COMM_FNB_4';

import COMM_WS_1 from '@salesforce/resourceUrl/COMM_WS_1';
import COMM_WS_2 from '@salesforce/resourceUrl/COMM_WS_2';
import COMM_WS_3 from '@salesforce/resourceUrl/COMM_WS_3';
import COMM_WS_4 from '@salesforce/resourceUrl/COMM_WS_4';

export default class CommercialShowcase extends LightningElement {
  showRegistrationPopup = false;

  @api rooms = [
    {
      key: 'lobby',
      title: 'Lobby & Reception',
      tagline: 'First impressions that last',
      features: [
        'Client-friendly reception layouts',
        'Statement concierge desks',
        'Material palettes for high traffic',
        'Wayfinding & signage solutions'
      ],
      images: [COMM_LOBBY_1, COMM_LOBBY_2, COMM_LOBBY_3, COMM_LOBBY_4],
      deliverables: [
        'Concept boards & finishes',
        'Reception furniture plan',
        'Lighting & electrical layout'
      ]
    },
    {
      key: 'office',
      title: 'Office Interiors',
      tagline: 'Productive, flexible workplace design',
      features: [
        'Open plan & focus zones',
        'Collaborative hubs',
        'Ergonomic workstation layouts',
        'Phone booth & quiet pods'
      ],
      images: [COMM_OFFICE_1, COMM_OFFICE_2, COMM_OFFICE_3, COMM_OFFICE_4],
      deliverables: [
        'Zoning & workstation schedules',
        'Joinery details & finishes',
        'Acoustic & lighting strategy'
      ]
    },
    {
      key: 'conference',
      title: 'Conference & Boardrooms',
      tagline: 'High-impact meeting spaces',
      features: [
        'AV-integrated boardrooms',
        'Acoustic treatments',
        'Flexible table layouts',
        'Executive finishes'
      ],
      images: [COMM_CONF_1, COMM_CONF_2, COMM_CONF_3, COMM_CONF_4],
      deliverables: [
        'AV coordination pack',
        'Furniture & joinery elevations',
        'Lighting & blackout plan'
      ]
    },
    {
      key: 'retail',
      title: 'Retail & Showrooms',
      tagline: 'Merchandising-forward retail design',
      features: [
        'Fixture planning & flow',
        'Feature walls & displays',
        'POS ergonomics',
        'Material durability schedules'
      ],
      images: [COMM_RETAIL_1, COMM_RETAIL_2, COMM_RETAIL_3, COMM_RETAIL_4],
      deliverables: [
        'Display & fixture plans',
        'Material swatches & finishes',
        'Lighting for product highlighting'
      ]
    },
    {
      key: 'fnb',
      title: 'F&B Interiors',
      tagline: 'Ambience-led dining experiences',
      features: [
        'Seating layouts & capacity planning',
        'Back-of-house coordination',
        'Lighting to match mood',
        'Durable finishes for service'
      ],
      images: [COMM_FNB_1, COMM_FNB_2, COMM_FNB_3, COMM_FNB_4],
      deliverables: [
        'Seating & circulation plan',
        'Kitchen adjacencies',
        'Finish & fittings schedule'
      ]
    },
    {
      key: 'workspace',
      title: 'Flexible Workspaces',
      tagline: 'Hybrid-ready coworking & hubs',
      features: [
        'Bookable hubs & pods',
        'Adaptable furniture systems',
        'Tech-ready meeting spots'
      ],
      images: [COMM_WS_1, COMM_WS_2, COMM_WS_3, COMM_WS_4],
      deliverables: [
        'Booking & zoning strategy',
        'Furniture spec sheets',
        'Power & data layouts'
      ]
    }
  ];

  modalOpen = false;
  activeRoom = null;
  activeIndex = 0;

  _observer = null;
  _observed = false;
  _animatingImage = false;
  _onStageMouse = null;
  _onStageLeave = null;

  connectedCallback() {
    this.rooms = this.rooms.map((r) => {
      const copy = { ...r };
      copy.placeholder = copy.images && copy.images.length ? copy.images[0] : '';
      return copy;
    });

    if ('IntersectionObserver' in window) {
      this._observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const el = entry.target;
            const cards = Array.from(this.template ? this.template.querySelectorAll('.rs-card') : []);
            const idx = cards.indexOf(el);
            const delay = Math.min(300, Math.max(0, idx * 80));
            el.style.transitionDelay = `${delay}ms`;
            el.classList.add('in-view');
            if (this._observer && entry.target) {
              this._observer.unobserve(entry.target);
            }
          }
        });
      }, { threshold: 0.15 });
    }
  }

  renderedCallback() {
    if (!this._observed) {
      const cards = this.template.querySelectorAll('.rs-card');
      if (cards && cards.length && this._observer) {
        cards.forEach((c) => this._observer.observe(c));
        this._observed = true;
      } else if (cards && cards.length && !this._observer) {
        cards.forEach((c, idx) => {
          c.classList.add('in-view');
          c.style.transitionDelay = `${Math.min(300, idx * 60)}ms`;
        });
        this._observed = true;
      }
    }

    if (this.modalOpen) {
      setTimeout(() => {
        const backdrop = this.template.querySelector('.rs-backdrop');
        const modal = this.template.querySelector('.rs-modal');
        const img = this.template.querySelector('.car-img');

        if (backdrop) {
          backdrop.classList.add('open');
        }
        if (modal) {
          modal.classList.add('open');
        }

        if (img) {
          img.classList.add('pop-in');
          img.classList.add('kenburns');
          setTimeout(() => img.classList.remove('pop-in'), 520);
        }

        if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
          const stage = this.template.querySelector('.car-stage');
          if (stage && img) {
            this._onStageMouse = (e) => {
              const rect = stage.getBoundingClientRect();
              const x = (e.clientX - rect.left) / rect.width - 0.5;
              const y = (e.clientY - rect.top) / rect.height - 0.5;
              const tx = (x * 8).toFixed(2);
              const ty = (y * 6).toFixed(2);
              img.style.transform = `translate(${tx}px, ${ty}px) scale(1.02)`;
            };
            this._onStageLeave = () => {
              img.style.transform = '';
            };
            stage.addEventListener('mousemove', this._onStageMouse);
            stage.addEventListener('mouseleave', this._onStageLeave);
          }
        }

        this.updateThumbs();
        this.scrollThumbIntoView();
      }, 20);
    }
  }

  disconnectedCallback() {
    if (this._observer) {
      this._observer.disconnect();
      this._observer = null;
    }
    this._removeParallaxListeners();
  }

  openRoom(evt) {
    const key = evt.currentTarget.dataset.key;
    if (!key) {
      return;
    }

    const room = this.rooms.find((r) => r.key === key);
    if (!room) {
      return;
    }

    this.activeRoom = room;
    this.activeIndex = 0;
    this.modalOpen = true;

    setTimeout(() => {
      const modal = this.template.querySelector('.rs-modal');
      if (modal) {
        modal.focus();
      }
      this.updateThumbs();
      this.scrollThumbIntoView();
    }, 40);
  }

  closeModal() {
    this._removeParallaxListeners();

    const modal = this.template.querySelector('.rs-modal');
    const backdrop = this.template.querySelector('.rs-backdrop');
    const img = this.template.querySelector('.car-img');

    if (img) {
      img.classList.remove('kenburns');
      img.style.transform = '';
    }

    if (modal) {
      modal.classList.remove('open');
    }
    if (backdrop) {
      backdrop.classList.remove('open');
    }

    const onEnd = (e) => {
      if (e && e.target !== modal) {
        return;
      }
      this.modalOpen = false;
      this.activeRoom = null;
      this.activeIndex = 0;
      if (modal) {
        modal.removeEventListener('transitionend', onEnd);
      }
    };

    if (modal) {
      modal.addEventListener('transitionend', onEnd);
      setTimeout(() => {
        if (this.modalOpen) {
          this.modalOpen = false;
          this.activeRoom = null;
          this.activeIndex = 0;
        }
      }, 420);
    } else {
      this.modalOpen = false;
      this.activeRoom = null;
      this.activeIndex = 0;
    }
  }

  closeModalAndOpenPopup() {
    this._removeParallaxListeners();

    const modal = this.template.querySelector('.rs-modal');
    const backdrop = this.template.querySelector('.rs-backdrop');
    const img = this.template.querySelector('.car-img');

    if (img) {
      img.classList.remove('kenburns');
      img.style.transform = '';
    }

    if (modal) {
      modal.classList.remove('open');
    }

    if (backdrop) {
      backdrop.classList.remove('open');
    }

    this.modalOpen = false;
    this.activeRoom = null;
    this.activeIndex = 0;

    requestAnimationFrame(() => {
      this.showRegistrationPopup = true;
    });
  }

  _removeParallaxListeners() {
    const stage = this.template ? this.template.querySelector('.car-stage') : null;
    if (stage) {
      if (this._onStageMouse) {
        stage.removeEventListener('mousemove', this._onStageMouse);
      }
      if (this._onStageLeave) {
        stage.removeEventListener('mouseleave', this._onStageLeave);
      }
    }
    this._onStageMouse = null;
    this._onStageLeave = null;

    const img = this.template ? this.template.querySelector('.car-img') : null;
    if (img) {
      img.style.transform = '';
      img.classList.remove('pop-in');
      img.classList.remove('kenburns');
    }
  }

  handleBackdrop(evt) {
    if (evt.target.classList && evt.target.classList.contains('rs-backdrop')) {
      this.closeModal();
    }
  }

  modalKeydown(evt) {
    if (!this.modalOpen) {
      return;
    }
    if (evt.key === 'Escape') {
      this.closeModal();
    } else if (evt.key === 'ArrowRight') {
      this.nextImage();
    } else if (evt.key === 'ArrowLeft') {
      this.prevImage();
    }
  }

  _animateImageChange(newIndex) {
    if (this._animatingImage) {
      return;
    }

    if (!this.activeRoom || !this.template) {
      this.activeIndex = newIndex;
      this.updateThumbs();
      this.scrollThumbIntoView();
      return;
    }

    const img = this.template.querySelector('.car-img');
    if (!img) {
      this.activeIndex = newIndex;
      this.updateThumbs();
      this.scrollThumbIntoView();
      return;
    }

    this._animatingImage = true;
    img.classList.remove('fade-in', 'pop-in');
    img.classList.add('fade-out');

    const newSrc = this.activeRoom.images[newIndex];
    const pre = new Image();
    pre.src = newSrc;

    let didFinish = false;
    const safetyTimeout = 1200;
    const safety = setTimeout(() => {
      if (didFinish) {
        return;
      }
      didFinish = true;
      this.activeIndex = newIndex;
      requestAnimationFrame(() => {
        img.classList.remove('fade-out');
        img.classList.add('fade-in', 'pop-in', 'kenburns');
        setTimeout(() => {
          img.classList.remove('fade-in', 'pop-in');
          this._animatingImage = false;
          this.updateThumbs();
          this.scrollThumbIntoView();
        }, 420);
      });
    }, safetyTimeout);

    pre.onload = () => {
      if (didFinish) {
        return;
      }
      didFinish = true;
      clearTimeout(safety);
      setTimeout(() => {
        this.activeIndex = newIndex;
        requestAnimationFrame(() => {
          img.classList.remove('fade-out');
          img.classList.add('fade-in', 'pop-in', 'kenburns');
          setTimeout(() => {
            img.classList.remove('fade-in', 'pop-in');
            this._animatingImage = false;
            this.updateThumbs();
            this.scrollThumbIntoView();
          }, 420);
        });
      }, 80);
    };

    pre.onerror = () => {
      if (didFinish) {
        return;
      }
      didFinish = true;
      clearTimeout(safety);
      this.activeIndex = newIndex;
      requestAnimationFrame(() => {
        img.classList.remove('fade-out');
        img.classList.add('fade-in', 'kenburns');
        setTimeout(() => {
          img.classList.remove('fade-in');
          this._animatingImage = false;
          this.updateThumbs();
          this.scrollThumbIntoView();
        }, 420);
      });
    };
  }

  nextImage() {
    if (this._animatingImage || !this.activeRoom) {
      return;
    }
    const len = this.activeRoom.images.length;
    const newIndex = (this.activeIndex + 1) % len;
    this._animateImageChange(newIndex);
  }

  prevImage() {
    if (this._animatingImage || !this.activeRoom) {
      return;
    }
    const len = this.activeRoom.images.length;
    const newIndex = (this.activeIndex - 1 + len) % len;
    this._animateImageChange(newIndex);
  }

  goToImage(index) {
    if (this._animatingImage || !this.activeRoom) {
      return;
    }
    const len = this.activeRoom.images.length;
    const idx = Math.max(0, Math.min(len - 1, index));
    this._animateImageChange(idx);
  }

  handleThumbClick(evt) {
    const idx = parseInt(evt.currentTarget.dataset.idx, 10);
    if (Number.isNaN(idx)) {
      return;
    }
    this.goToImage(idx);
  }

  updateThumbs() {
    const strip = this.template ? this.template.querySelector('.thumb-strip') : null;
    if (!strip) {
      return;
    }
    const buttons = Array.from(strip.querySelectorAll('.thumb-btn'));
    buttons.forEach((btn, idx) => {
      if (idx === this.activeIndex) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });
  }

  scrollThumbIntoView() {
    setTimeout(() => {
      const strip = this.template ? this.template.querySelector('.thumb-strip') : null;
      if (!strip) {
        return;
      }
      const btns = strip.querySelectorAll('.thumb-btn');
      const active = btns && btns[this.activeIndex];
      if (active && typeof active.scrollIntoView === 'function') {
        active.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
      }
    }, 90);
  }

  get currentImage() {
    return this.activeRoom ? this.activeRoom.images[this.activeIndex] : '';
  }

  get currentCaption() {
    return this.activeRoom ? `${this.activeRoom.title} — View ${this.activeIndex + 1}` : '';
  }

  handleModalAction(evt) {
    const key = evt.currentTarget?.dataset?.key || (this.activeRoom && this.activeRoom.key);

    this.dispatchEvent(new CustomEvent('bookconsult', {
      detail: { pillar: 'commercial', room: key },
      bubbles: true,
      composed: true
    }));

    this.closeModalAndOpenPopup();
  }

  handleClosePopup() {
    this.showRegistrationPopup = false;
  }
}