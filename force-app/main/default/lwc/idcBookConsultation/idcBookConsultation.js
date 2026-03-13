import { LightningElement } from 'lwc';
import appointmentImage from '@salesforce/resourceUrl/appointmentImage';
import { NavigationMixin } from 'lightning/navigation';
import Arelia_Site_Label from '@salesforce/label/c.Arelia_Site_Label';

export default class IdcBookConsultation extends NavigationMixin(LightningElement) {
  appointmentImg = appointmentImage;
  siteUrl = Arelia_Site_Label;

  // internals
  _observer = null;
  _observed = false;
  _parallaxMove = null;
  _parallaxLeave = null;

  connectedCallback() {
    if ('IntersectionObserver' in window) {
      this._observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            const root = this.template.querySelector('.consult-inner');
            if (root) {
              root.classList.add('in-view');

              // staggered reveals for right column (content)
              const right = this.template.querySelector('.consult-right');
              if (right) {
                const elems = ['.eyebrow', '.headline', '.subtext', '.cta-button'];
                elems.forEach((sel, idx) => {
                  const el = right.querySelector(sel);
                  if (el) {
                    el.classList.add('reveal');
                    el.style.transitionDelay = `${80 + idx * 80}ms`;
                  }
                });
                setTimeout(() => right.classList.add('in-view'), 120);
              }

              // pop-in image-card and attach parallax if allowed
              const card = this.template.querySelector('.image-card');
              const img = this.template.querySelector('.consult-img');
              if (card) {
                card.classList.add('pop-in');
                setTimeout(() => card.classList.remove('pop-in'), 520);
              }

              if (img && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
                setTimeout(() => img.classList.add('kenburns'), 600);

                const stage = this.template.querySelector('.image-card');
                if (stage) {
                  if (!this._parallaxMove) {
                    this._parallaxMove = (e) => {
                      const rect = stage.getBoundingClientRect();
                      const x = ((e.clientX - rect.left) / rect.width - 0.5);
                      const y = ((e.clientY - rect.top) / rect.height - 0.5);
                      const tx = (x * 8).toFixed(2);
                      const ty = (y * 6).toFixed(2);
                      img.style.transform = `translate(${tx}px, ${ty}px) scale(1.01)`;
                    };
                    this._parallaxLeave = () => {
                      img.style.transform = '';
                    };
                    stage.addEventListener('mousemove', this._parallaxMove);
                    stage.addEventListener('mouseleave', this._parallaxLeave);
                  }
                }
              }

              if (this._observer && entry.target) this._observer.unobserve(entry.target);
            }
          }
        });
      }, { threshold: 0.12 });
    }
  }

  renderedCallback() {
    if (!this._observed) {
      const el = this.template.querySelector('.consult-inner');
      if (el && this._observer) {
        this._observer.observe(el);
        this._observed = true;
      } else if (el && !('IntersectionObserver' in window)) {
        el.classList.add('in-view');
        const right = this.template.querySelector('.consult-right');
        if (right) right.classList.add('in-view');
      }
    }
  }

  disconnectedCallback() {
    if (this._observer) {
      this._observer.disconnect();
      this._observer = null;
    }
    const stage = this.template.querySelector('.image-card');
    if (stage) {
      if (this._parallaxMove) stage.removeEventListener('mousemove', this._parallaxMove);
      if (this._parallaxLeave) stage.removeEventListener('mouseleave', this._parallaxLeave);
    }
    this._parallaxMove = null;
    this._parallaxLeave = null;
  }

  handleBookClick() {
    // navigate to registration form — keeps same pattern you used
    this[NavigationMixin.Navigate]({
      type: 'standard__webPage',
      attributes: {
        url: `${this.siteUrl}registration-form`
      }
    });
  }
}