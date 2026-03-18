import { LightningElement } from 'lwc';
import COVER_VIDEO from '@salesforce/resourceUrl/hospitality_portfolio_video';
import COVER_POSTER from '@salesforce/resourceUrl/HospitalityCover';

export default class IdcHospitalityCover extends LightningElement {

    coverVideo = COVER_VIDEO;
    posterImage = COVER_POSTER;

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