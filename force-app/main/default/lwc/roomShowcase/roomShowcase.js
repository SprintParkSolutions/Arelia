import { LightningElement, api } from 'lwc';

// image static resource imports (keep yours)
import LIVING_1 from '@salesforce/resourceUrl/living_1';
import LIVING_2 from '@salesforce/resourceUrl/living_2';
import LIVING_3 from '@salesforce/resourceUrl/living_3';
import LIVING_4 from '@salesforce/resourceUrl/living_4';
import BEDROOM_1 from '@salesforce/resourceUrl/bedroom_1';
import BEDROOM_2 from '@salesforce/resourceUrl/bedroom_2';
import BEDROOM_3 from '@salesforce/resourceUrl/bedroom_3';
import BEDROOM_4 from '@salesforce/resourceUrl/bedroom_4';
import KITCHEN_1 from '@salesforce/resourceUrl/kitchen_1';
import KITCHEN_2 from '@salesforce/resourceUrl/kitchen_2';
import KITCHEN_3 from '@salesforce/resourceUrl/kitchen_3';
import KITCHEN_4 from '@salesforce/resourceUrl/kitchen_4';
import BATH_1 from '@salesforce/resourceUrl/bath_1';
import BATH_2 from '@salesforce/resourceUrl/bath_2';
import BATH_3 from '@salesforce/resourceUrl/bath_3';
import BATH_4 from '@salesforce/resourceUrl/bath_4';
import DINING_1 from '@salesforce/resourceUrl/dining_1';
import DINING_2 from '@salesforce/resourceUrl/dining_2';
import DINING_3 from '@salesforce/resourceUrl/dining_3';
import DINING_4 from '@salesforce/resourceUrl/dining_4';
import BALCONY_1 from '@salesforce/resourceUrl/balcony_1';
import BALCONY_2 from '@salesforce/resourceUrl/balcony_2';
import BALCONY_3 from '@salesforce/resourceUrl/balcony_3';
import BALCONY_4 from '@salesforce/resourceUrl/balcony_4';

import SITE_BASE_URL from '@salesforce/label/c.Arelia_Site_Label';
import REGISTRATION_FORM_URL from '@salesforce/label/c.Registration_Form_URL';

export default class RoomShowcase extends LightningElement {

  baseUrl = SITE_BASE_URL;

  get registrationFormUrl() {
    return this.baseUrl + REGISTRATION_FORM_URL;
  }

  @api rooms = [
    {
      key: 'living',
      title: 'Living Room',
      tagline: 'Modern living designs & layouts',
      features: [
        'Sofa layout examples',
        'TV units & media walls',
        'False ceiling styles',
        'Lighting ideas',
        'Wall textures'
      ],
      images: [LIVING_1, LIVING_2, LIVING_3, LIVING_4],
      deliverables: [
        'Concept moodboard & material palette',
        '2D layout & furniture plan',
        'Lighting plan & fixtures list',
        '3D visualizations (2 views)'
      ]
    },
    {
      key: 'bedroom',
      title: 'Bedrooms',
      tagline: 'Master, guest & kids bedroom solutions',
      features: [
        'Master bedroom design',
        'Guest & kids layouts',
        'Wardrobes & storage',
        'Study & dressing area'
      ],
      images: [BEDROOM_1, BEDROOM_2, BEDROOM_3, BEDROOM_4],
      deliverables: [
        'Wardrobe layout & joinery details',
        'Bespoke headboard treatments',
        'Lighting & soft-furnishing plan',
        '3D renders for approvals'
      ]
    },
    {
      key: 'kitchen',
      title: 'Kitchen',
      tagline: 'Modular kitchens & smart storage',
      features: [
        'L-shape, Island, Parallel',
        'Smart storage solutions',
        'Countertop & backsplash options',
        'Appliances integration'
      ],
      images: [KITCHEN_1, KITCHEN_2, KITCHEN_3, KITCHEN_4],
      deliverables: [
        'Cabinet elevations & details',
        'Plumbing & electrical coordination',
        'Appliance layout & venting plan',
        'Material & finish schedule'
      ]
    },
    {
      key: 'bathroom',
      title: 'Bathrooms',
      tagline: 'Functional & elegant bathroom designs',
      features: [
        'Vanity styles',
        'Glass partitions',
        'Tiles & finish options',
        'Storage & mood lighting'
      ],
      images: [BATH_1, BATH_2, BATH_3, BATH_4],
      deliverables: [
        'Sanitary layouts & drainage plan',
        'Vanity & storage designs',
        'Tiling & waterproofing spec',
        'Fixture & fittings schedule'
      ]
    },
    {
      key: 'dining',
      title: 'Dining',
      tagline: 'Dining setups & lighting',
      features: [
        'Lighting & pendants',
        'Table layouts',
        'Wall décor ideas',
        'Niche designs'
      ],
      images: [DINING_1, DINING_2, DINING_3, DINING_4],
      deliverables: [
        'Dining layout & furniture plan',
        'Lighting scheme & dimming',
        'Wall finish suggestions',
        'Styling & table settings'
      ]
    },
    {
      key: 'balcony',
      title: 'Balcony / Outdoor',
      tagline: 'Outdoor seating & greenery',
      features: [
        'Seating ideas',
        'Greenery & planters',
        'Lighting for evenings'
      ],
      images: [BALCONY_1, BALCONY_2, BALCONY_3, BALCONY_4],
      deliverables: [
        'Outdoor seating layouts',
        'Planting & planter specifications',
        'Outdoor lighting & wiring',
        'Material choices for weather'
      ]
    }
  ];

  modalOpen = false;
  activeRoom = null;
  activeIndex = 0;

  _observer = null;
  _observed = false;
  _animatingImage = false;

  // parallax handlers
  _onStageMouse = null;
  _onStageLeave = null;

  connectedCallback() {
    // ensure placeholder is set
    this.rooms = this.rooms.map(r => {
      const copy = { ...r };
      copy.placeholder = (copy.images && copy.images.length) ? copy.images[0] : (copy.placeholder || '');
      return copy;
    });

    if ('IntersectionObserver' in window) {
      this._observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          const el = entry.target;
          if (entry.isIntersecting) {
            const cards = Array.from(this.template ? this.template.querySelectorAll('.rs-card') : []);
            const idx = cards.indexOf(el);
            const delay = Math.min(300, Math.max(0, idx * 80));
            el.style.transitionDelay = `${delay}ms`;
            el.classList.add('in-view');
            if (this._observer && entry.target) this._observer.unobserve(entry.target);
          }
        });
      }, { threshold: 0.15 });
    }
  }

  renderedCallback() {
    // observe cards once
    if (!this._observed) {
      const cards = this.template.querySelectorAll('.rs-card');
      if (cards && cards.length && this._observer) {
        cards.forEach(c => this._observer.observe(c));
        this._observed = true;
      } else if (cards && cards.length && !this._observer) {
        // fallback reveal
        cards.forEach((c, idx) => {
          c.classList.add('in-view');
          c.style.transitionDelay = `${Math.min(300, idx * 60)}ms`;
        });
        this._observed = true;
      }
    }

    // modal open visual hooks
    if (this.modalOpen) {
      setTimeout(() => {
        const backdrop = this.template.querySelector('.rs-backdrop');
        const modal = this.template.querySelector('.rs-modal');
        const img = this.template.querySelector('.car-img');
        if (backdrop) backdrop.classList.add('open');
        if (modal) modal.classList.add('open');

        if (img) {
          img.classList.add('pop-in');
          img.classList.add('kenburns');
          setTimeout(() => img.classList.remove('pop-in'), 520);
        }

        // parallax listeners if allowed
        if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
          const stage = this.template.querySelector('.car-stage');
          if (stage && img) {
            this._onStageMouse = (e) => {
              const rect = stage.getBoundingClientRect();
              const x = ((e.clientX - rect.left) / rect.width - 0.5);
              const y = ((e.clientY - rect.top) / rect.height - 0.5);
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

        // sync thumbnails
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
    if (!key) return;
    const room = this.rooms.find(r => r.key === key);
    if (!room) return;
    this.activeRoom = room;
    this.activeIndex = 0;
    this.modalOpen = true;
    // ensure focus flows into modal for keyboard users
    setTimeout(() => {
      const modal = this.template.querySelector('.rs-modal');
      if (modal) modal.focus();
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

    if (modal) modal.classList.remove('open');
    if (backdrop) backdrop.classList.remove('open');

    const onEnd = (e) => {
      if (e && e.target !== modal) return;
      this.modalOpen = false;
      this.activeRoom = null;
      this.activeIndex = 0;
      if (modal) modal.removeEventListener('transitionend', onEnd);
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

  _removeParallaxListeners() {
    const stage = this.template ? this.template.querySelector('.car-stage') : null;
    if (stage) {
      if (this._onStageMouse) stage.removeEventListener('mousemove', this._onStageMouse);
      if (this._onStageLeave) stage.removeEventListener('mouseleave', this._onStageLeave);
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
    if (!this.modalOpen) return;
    if (evt.key === 'Escape') this.closeModal();
    else if (evt.key === 'ArrowRight') this.nextImage();
    else if (evt.key === 'ArrowLeft') this.prevImage();
  }

  // image animation swap (keeps your fade/pop-in)
  _animateImageChange(newIndex) {
    if (this._animatingImage) return;
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
      if (didFinish) return;
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
      if (didFinish) return;
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
      if (didFinish) return;
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
    if (!this.activeRoom) return;
    const len = this.activeRoom.images.length;
    const newIndex = (this.activeIndex + 1) % len;
    this._animateImageChange(newIndex);
  }

  prevImage() {
    if (!this.activeRoom) return;
    const len = this.activeRoom.images.length;
    const newIndex = (this.activeIndex - 1 + len) % len;
    this._animateImageChange(newIndex);
  }

  goToImage(index) {
    if (this._animatingImage) return;
    if (!this.activeRoom) return;
    const len = this.activeRoom.images.length;
    const idx = Math.max(0, Math.min(len - 1, index));
    this._animateImageChange(idx);
  }

  handleThumbClick(evt) {
    const idx = parseInt(evt.currentTarget.dataset.idx, 10);
    if (Number.isNaN(idx)) return;
    this.goToImage(idx);
  }

  updateThumbs() {
    const strip = this.template ? this.template.querySelector('.thumb-strip') : null;
    if (!strip) return;
    const buttons = Array.from(strip.querySelectorAll('.thumb-btn'));
    buttons.forEach((btn, idx) => {
      if (idx === this.activeIndex) btn.classList.add('active');
      else btn.classList.remove('active');
    });
  }

  scrollThumbIntoView() {
    setTimeout(() => {
      const strip = this.template ? this.template.querySelector('.thumb-strip') : null;
      if (!strip) return;
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

  emitExploreMoodboard(evt) {
    const key = evt.currentTarget.dataset.key || (this.activeRoom && this.activeRoom.key);
    if (!key) return;
    this.dispatchEvent(new CustomEvent('exploremoodboard', { detail: { key }, bubbles: true, composed: true }));
  }

  handleModalAction(evt) {
    const key = evt.currentTarget?.dataset?.key || (this.activeRoom && this.activeRoom.key);

    // dispatch existing event for parent usage (analytics / tracking)
    this.dispatchEvent(new CustomEvent('bookconsult', {
      detail: { pillar: 'residential', room: key },
      bubbles: true,
      composed: true
    }));

    // close modal then navigate to registration form
    this.closeModal();
    // slight delay so close animation is visible
    setTimeout(() => {
      window.location.href = this.registrationFormUrl;
    }, 180);
  }
}