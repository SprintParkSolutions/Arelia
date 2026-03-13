import { LightningElement } from 'lwc';
import ABOUT_IMAGE from '@salesforce/resourceUrl/AboutUsImage1';
export default class LuxuryAboutSection extends LightningElement {
    aboutImageUrl = ABOUT_IMAGE;

    renderedCallback() {
    // Ensure this runs only once
    if (this._animInit) return;
    this._animInit = true;

    const container = this.template.querySelector('.luxury-about-container');
    if (!container) return;

    // If IO unsupported, show immediately
    if (!('IntersectionObserver' in window)) {
        container.classList.add('is-visible');
        return;
    }

    const io = new IntersectionObserver((entries, obs) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                container.classList.add('is-visible');
                obs.unobserve(entry.target);
            }
        });
    }, {
        root: null,
        threshold: 0.12,
        rootMargin: '0px 0px -8% 0px' // reveal a bit earlier
    });

    io.observe(container);
}

}