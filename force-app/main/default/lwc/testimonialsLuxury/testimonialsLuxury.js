import { LightningElement, api } from 'lwc';

export default class TestimonialsLuxury extends LightningElement {
  // public API: pass in testimonials array if you want to override defaults
  // each testimonial: { id, quote, name, role, avatar(optional URL) }
  @api testimonials = [
    {
      id: 't1',
      quote: 'They transformed our home into a calm, beautifully detailed space. The team understood our tastes immediately.',
      name: 'Ananya Reddy',
      role: 'Private Residence — Hyderabad',
      avatar: '' // optional static resource URL or external URL
    },
    {
      id: 't2',
      quote: 'A flawless process from concept to execution. Professional, punctual and completely reliable.',
      name: 'Rahul Mehta',
      role: 'Apex Tech HQ — Bangalore',
      avatar: ''
    },
    {
      id: 't3',
      quote: 'The attention to detail is remarkable — bespoke furniture and finishing that feels truly unique.',
      name: 'S. Kapoor',
      role: 'Luxury Villa — Goa',
      avatar: ''
    }
  ];

  activeIndex = 0;
  autoplayInterval = null;
  autoplayDelay = 5000; // 5s per highlight

  // Process testimonials to include computed classes, index and active flag.
  // The template uses only property access (t._cardClass, t._dotClass, t._isActive, t.index)
  get processedTestimonials() {
    const len = this.testimonials ? this.testimonials.length : 0;
    const nextIndex = len ? (this.activeIndex + 1) % len : 0;

    return (this.testimonials || []).map((t, idx) => {
      const isActive = idx === this.activeIndex;
      const isNext = idx === nextIndex;

      let cardClass = 'card';
      if (isActive) {
        cardClass = 'card active';
      } else if (isNext) {
        cardClass = 'card next';
      }

      const dotClass = isActive ? 'dot active' : 'dot';

      return {
        ...t,
        index: idx,
        _isActive: isActive,
        _cardClass: cardClass,
        _dotClass: dotClass
      };
    });
  }

  connectedCallback() {
    if (this.autoplayDelay && this.testimonials && this.testimonials.length > 1) {
      this.startAutoplay();
    }
  }

  disconnectedCallback() {
    this.stopAutoplay();
  }

  startAutoplay() {
    this.stopAutoplay();
    this.autoplayInterval = setInterval(() => {
      this.next();
    }, this.autoplayDelay);
  }

  stopAutoplay() {
    if (this.autoplayInterval) {
      clearInterval(this.autoplayInterval);
      this.autoplayInterval = null;
    }
  }

  next() {
    const nextIndex = (this.activeIndex + 1) % this.testimonials.length;
    this.setActive(nextIndex);
  }

  prev() {
    const prevIndex = (this.activeIndex - 1 + this.testimonials.length) % this.testimonials.length;
    this.setActive(prevIndex);
  }

  goTo(event) {
    const idx = Number(event.currentTarget.dataset.index);
    if (!Number.isNaN(idx)) {
      this.setActive(idx);
    }
  }

  setActive(index) {
    this.activeIndex = index;
    // restart autoplay so the user sees full delay after manual interaction
    if (this.autoplayDelay) {
      this.startAutoplay();
    }
  }

  handleFocus() {
    // pause autoplay when keyboard navigating into a card
    this.stopAutoplay();
  }
}