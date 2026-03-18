import { LightningElement } from 'lwc';
import COMMERCIAL_VIDEO from '@salesforce/resourceUrl/commercial_portfolio_video';
import COMMERCIAL_POSTER from '@salesforce/resourceUrl/CommericalCover';

export default class IdcCommercialPortfolioCover extends LightningElement {
    coverVideo = COMMERCIAL_VIDEO;
    posterImage = COMMERCIAL_POSTER;
    showRegistrationPopup = false;
    _observerInitialized = false;

    renderedCallback() {
        if (this._observerInitialized) {
            return;
        }
        this._observerInitialized = true;

        const heroEl = this.template.querySelector('[data-hero]');
        if (!heroEl) {
            return;
        }

        const io = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    heroEl.classList.add('in-view');
                    io.unobserve(heroEl);
                }
            });
        }, { threshold: 0.15 });

        io.observe(heroEl);
    }

    handleOpenPopup() {
        this.showRegistrationPopup = true;
    }

    handleClosePopup() {
        this.showRegistrationPopup = false;
    }
}