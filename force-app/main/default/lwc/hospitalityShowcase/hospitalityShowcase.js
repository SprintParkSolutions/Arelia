import { LightningElement, api } from 'lwc';

// Images: replace these imports with your hospitality static resources
import HOTEL_1 from '@salesforce/resourceUrl/hotel_1';
import HOTEL_2 from '@salesforce/resourceUrl/hotel_2';
import HOTEL_3 from '@salesforce/resourceUrl/hotel_3';
import RESTAURANT_1 from '@salesforce/resourceUrl/restaurant_1';
import RESTAURANT_2 from '@salesforce/resourceUrl/restaurant_2';
import RESTAURANT_3 from '@salesforce/resourceUrl/restaurant_3';
import BAR_1 from '@salesforce/resourceUrl/bar_1';
import BAR_2 from '@salesforce/resourceUrl/bar_2';
import BAR_3 from '@salesforce/resourceUrl/bar_3';
import RESORT_1 from '@salesforce/resourceUrl/resort_1';
import RESORT_2 from '@salesforce/resourceUrl/resort_2';
import RESORT_3 from '@salesforce/resourceUrl/resort_3';
import BANQUET_1 from '@salesforce/resourceUrl/banquet_1';
import BANQUET_2 from '@salesforce/resourceUrl/banquet_2';
import BANQUET_3 from '@salesforce/resourceUrl/banquet_3';
import BOUTIQUE_1 from '@salesforce/resourceUrl/boutique_1';
import BOUTIQUE_2 from '@salesforce/resourceUrl/boutique_2';
import BOUTIQUE_3 from '@salesforce/resourceUrl/boutique_3';

export default class HospitalityShowcase extends LightningElement {
  showRegistrationPopup = false;

  @api rooms = [
    {
      key: 'hotel-suites',
      title: 'Hotel Suites & Luxury Rooms',
      tagline: 'Designs for premium guest experiences',
      features: [
        'Luxury suite planning',
        'Executive & family suites',
        'Mood lighting & ambience',
        'Bespoke linen & fixtures'
      ],
      images: [HOTEL_1, HOTEL_2, HOTEL_3],
      deliverables: [
        'Concept moodboard & material palette',
        'Suite layout & furniture plan',
        'Lighting & AV coordination',
        '3D visualizations for approvals'
      ]
    },
    {
      key: 'restaurant-interiors',
      title: 'Restaurant & Café Interiors',
      tagline: 'Ambience-led seating & service flow',
      features: [
        'Seating layouts & capacity planning',
        'Back-of-house coordination',
        'Feature lighting & acoustics',
        'Durable finishes for hospitality'
      ],
      images: [RESTAURANT_1, RESTAURANT_2, RESTAURANT_3],
      deliverables: [
        'Dining layout & seating plan',
        'Lighting scheme & pendants',
        'Service & circulation plan',
        'Material & finish schedule'
      ]
    },
    {
      key: 'bar-lounge',
      title: 'Bar & Lounge Design',
      tagline: 'Signature bars & VIP lounges',
      features: [
        'Feature bar counters',
        'Acoustic treatments',
        'VIP seating & service zones',
        'Mood & feature lighting'
      ],
      images: [BAR_1, BAR_2, BAR_3],
      deliverables: [
        'Bar elevations & detailing',
        'Acoustic & lighting coordination',
        'VIP seating layout',
        'Bar service ergonomics'
      ]
    },
    {
      key: 'resort-spa',
      title: 'Resort & Spa',
      tagline: 'Wellness zones & landscape integration',
      features: [
        'Serene spa suites',
        'Wellness & treatment zones',
        'Landscape-led design',
        'Water features & finishes'
      ],
      images: [RESORT_1, RESORT_2, RESORT_3],
      deliverables: [
        'Spa layout & flow diagrams',
        'Material palette for wellness',
        'Landscape & water feature coordination',
        'Lighting & sensory design'
      ]
    },
    {
      key: 'banquet-halls',
      title: 'Banquet Halls & Event Spaces',
      tagline: 'Flexible event-ready layouts',
      features: [
        'Flexible seating plans',
        'AV-ready design & rigging',
        'Stage & staging solutions',
        'Catering & service flow'
      ],
      images: [BANQUET_1, BANQUET_2, BANQUET_3],
      deliverables: [
        'Event layout & zoning',
        'Stage & AV integration',
        'Catering flow & services plan',
        'Finishes & furniture pack'
      ]
    },
    {
      key: 'boutique-hotels',
      title: 'Boutique Hotels & BnB',
      tagline: 'Character-driven intimate stays',
      features: [
        'Local craft integration',
        'Characterful interiors',
        'Tailored guest experiences',
        'Efficient small-footprint design'
      ],
      images: [BOUTIQUE_1, BOUTIQUE_2, BOUTIQUE_3],
      deliverables: [
        'Character-led concept boards',
        'Guest room layouts & joinery',
        'Local material sourcing',
        'Styled photography-ready finishes'
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
      copy.images = (copy.images || []).map((s) => ({ src: s, isVideo: this.isVideo(s) }));
      copy.placeholder = copy.images && copy.images.length ? copy.images[0].src : '';
      copy.isVideoPlaceholder = copy.images && copy.images.length ? copy.images[0].isVideo : false;
      return copy;
    });

    if ('IntersectionObserver' in window) {
      this._observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          const el = entry.target;
          if (entry.isIntersecting) {
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
        const img = this.template.querySelector('.car-img') || this.template.querySelector('.car-stage video');

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
              if (img) {
                img.style.transform = '';
              }
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
      this._applyCurrentMediaToStage();
    }, 40);
  }

  closeModal() {
    this._removeParallaxListeners();

    const backdrop = this.template.querySelector('.rs-backdrop');
    const modal = this.template.querySelector('.rs-modal');
    const img = this.template.querySelector('.car-img') || this.template.querySelector('.car-stage video');

    if (img) {
      img.classList.remove('kenburns');
      img.style.transform = '';
      if (img.tagName && img.tagName.toLowerCase() === 'video') {
        try {
          img.pause();
        } catch (e) {
          // ignore
        }
      }
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
    const img = this.template.querySelector('.car-img') || this.template.querySelector('.car-stage video');

    if (img) {
      img.classList.remove('kenburns');
      img.style.transform = '';
      if (img.tagName && img.tagName.toLowerCase() === 'video') {
        try {
          img.pause();
        } catch (e) {
          // ignore
        }
      }
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

    const img = this.template
      ? this.template.querySelector('.car-img') || this.template.querySelector('.car-stage video')
      : null;

    if (img) {
      img.style.transform = '';
      img.classList.remove('pop-in', 'kenburns');
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
    if (!this.activeRoom) {
      this.activeIndex = newIndex;
      return;
    }

    const stageImg = this.template.querySelector('.car-img');
    const stageVideo = this.template.querySelector('.car-stage video');

    const target = this.activeRoom.images[newIndex];
    const targetIsVideo = !!(target && target.isVideo);
    const targetSrc = target ? target.src : '';

    this._animatingImage = true;

    if (stageImg) {
      stageImg.classList.add('fade-out');
    }
    if (stageVideo) {
      stageVideo.classList.add('fade-out');
    }

    let didFinish = false;
    const safetyTimeout = 1400;
    const safety = setTimeout(() => {
      if (didFinish) {
        return;
      }
      didFinish = true;
      this.activeIndex = newIndex;
      this._finishAnimate(stageImg, stageVideo, targetIsVideo, targetSrc);
    }, safetyTimeout);

    if (targetIsVideo) {
      const v = document.createElement('video');
      v.preload = 'metadata';
      v.muted = true;
      v.playsInline = true;
      v.src = targetSrc;
      v.onloadedmetadata = () => {
        if (didFinish) {
          return;
        }
        didFinish = true;
        clearTimeout(safety);
        this.activeIndex = newIndex;
        this._finishAnimate(stageImg, stageVideo, targetIsVideo, targetSrc);
      };
      v.onerror = () => {
        if (didFinish) {
          return;
        }
        didFinish = true;
        clearTimeout(safety);
        this.activeIndex = newIndex;
        this._finishAnimate(stageImg, stageVideo, false, targetSrc);
      };
    } else {
      const pre = new Image();
      pre.src = targetSrc;
      pre.onload = () => {
        if (didFinish) {
          return;
        }
        didFinish = true;
        clearTimeout(safety);
        this.activeIndex = newIndex;
        this._finishAnimate(stageImg, stageVideo, targetIsVideo, targetSrc);
      };
      pre.onerror = () => {
        if (didFinish) {
          return;
        }
        didFinish = true;
        clearTimeout(safety);
        this.activeIndex = newIndex;
        this._finishAnimate(stageImg, stageVideo, false, targetSrc);
      };
    }
  }

  _finishAnimate(stageImg, stageVideo, targetIsVideo = undefined, targetSrc = undefined) {
    requestAnimationFrame(() => {
      if (targetIsVideo === undefined) {
        targetIsVideo = this.isVideo(this.currentImage);
        targetSrc = this.currentImage;
      }

      if (targetIsVideo) {
        let videoEl = this.template.querySelector('.car-stage video.car-img');
        if (!videoEl) {
          const imgEl = this.template.querySelector('.car-img');
          if (imgEl) {
            imgEl.remove();
          }
          const container = this.template.querySelector('.car-stage');
          const v = document.createElement('video');
          v.className = 'car-img';
          v.controls = true;
          v.autoplay = true;
          v.playsInline = true;
          v.muted = true;
          v.src = targetSrc;
          container.insertBefore(v, container.querySelector('.car-caption'));
          videoEl = v;
        } else {
          videoEl.src = targetSrc;
        }

        try {
          videoEl.play();
        } catch (e) {
          // ignore
        }

        videoEl.classList.remove('fade-out');
        videoEl.classList.add('fade-in', 'pop-in', 'kenburns');
        setTimeout(() => {
          videoEl.classList.remove('fade-in', 'pop-in');
          this._animatingImage = false;
          this.updateThumbs();
          this.scrollThumbIntoView();
        }, 420);
      } else {
        let imgEl = this.template.querySelector('.car-img');
        if (!imgEl) {
          const videoEl = this.template.querySelector('.car-stage video');
          if (videoEl) {
            videoEl.remove();
          }
          const img = document.createElement('img');
          img.className = 'car-img';
          img.alt = this.currentCaption;
          const container = this.template.querySelector('.car-stage');
          container.insertBefore(img, container.querySelector('.car-caption'));
          imgEl = img;
        }
        imgEl.src = targetSrc;
        imgEl.alt = this.currentCaption;

        imgEl.classList.remove('fade-out');
        imgEl.classList.add('fade-in', 'pop-in', 'kenburns');
        setTimeout(() => {
          imgEl.classList.remove('fade-in', 'pop-in');
          this._animatingImage = false;
          this.updateThumbs();
          this.scrollThumbIntoView();
        }, 420);
      }
    });
  }

  nextImage() {
    if (!this.activeRoom) {
      return;
    }
    const len = this.activeRoom.images.length;
    const newIndex = (this.activeIndex + 1) % len;
    this._animateImageChange(newIndex);
  }

  prevImage() {
    if (!this.activeRoom) {
      return;
    }
    const len = this.activeRoom.images.length;
    const newIndex = (this.activeIndex - 1 + len) % len;
    this._animateImageChange(newIndex);
  }

  goToImage(index) {
    if (this._animatingImage) {
      return;
    }
    if (!this.activeRoom) {
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
    return this.activeRoom && this.activeRoom.images && this.activeRoom.images[this.activeIndex]
      ? this.activeRoom.images[this.activeIndex].src
      : '';
  }

  get currentCaption() {
    return this.activeRoom ? `${this.activeRoom.title} — View ${this.activeIndex + 1}` : '';
  }

  get currentIsVideo() {
    return this.isVideo(this.currentImage);
  }

  isVideo(src) {
    if (!src || typeof src !== 'string') {
      return false;
    }
    return /\.(mp4|webm|mov)(\?.*)?$/i.test(src);
  }

  onMediaLoaded(evt) {
    const el = evt.currentTarget;
    if (el) {
      el.classList.add('pop-in', 'kenburns');
      setTimeout(() => el.classList.remove('pop-in'), 520);
    }
  }

  _applyCurrentMediaToStage() {
    const stage = this.template ? this.template.querySelector('.car-stage') : null;
    if (!stage || !this.activeRoom) {
      return;
    }

    const current = this.currentImage;
    if (this.isVideo(current)) {
      let v = stage.querySelector('video.car-img');
      if (!v) {
        const img = stage.querySelector('img.car-img');
        if (img) {
          img.remove();
        }
        v = document.createElement('video');
        v.className = 'car-img';
        v.controls = true;
        v.autoplay = true;
        v.playsInline = true;
        v.muted = true;
        stage.insertBefore(v, stage.querySelector('.car-caption'));
      }
      v.src = current;
      try {
        v.play();
      } catch (e) {
        // ignore
      }
    } else {
      let img = stage.querySelector('img.car-img');
      if (!img) {
        const videoEl = stage.querySelector('video.car-img');
        if (videoEl) {
          videoEl.remove();
        }
        img = document.createElement('img');
        img.className = 'car-img';
        img.alt = this.currentCaption;
        stage.insertBefore(img, stage.querySelector('.car-caption'));
      }
      img.src = current;
      img.alt = this.currentCaption;
    }

    this.updateThumbs();
    this.scrollThumbIntoView();
  }

  handleModalAction(evt) {
    const key = evt.currentTarget?.dataset?.key || (this.activeRoom && this.activeRoom.key);

    this.dispatchEvent(new CustomEvent('bookconsult', {
      detail: { pillar: 'hospitality', room: key },
      bubbles: true,
      composed: true
    }));

    this.closeModalAndOpenPopup();
  }

  handleClosePopup() {
    this.showRegistrationPopup = false;
  }
}