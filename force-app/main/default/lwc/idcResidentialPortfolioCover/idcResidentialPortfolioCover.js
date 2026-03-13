import { LightningElement } from 'lwc';
import COVER_VIDEO from '@salesforce/resourceUrl/residential_portfolio_video';
import COVER_POSTER from '@salesforce/resourceUrl/residential_portfolio_cover';
import { NavigationMixin } from 'lightning/navigation';
import SITE_BASE_URL from '@salesforce/label/c.Arelia_Site_Label';
import REGISTRATION_FORM_URL from '@salesforce/label/c.Registration_Form_URL';

export default class IdcResidentialPortfolioCover extends NavigationMixin(LightningElement) {
    coverVideo = COVER_VIDEO;
    posterImage = COVER_POSTER;

    baseUrl = SITE_BASE_URL;

    get registrationFormUrl() {
        return this.baseUrl + REGISTRATION_FORM_URL;
    }

    // final registration URL you provided
    registrationUrl = this.registrationFormUrl;

    renderedCallback() {
        if (this._observerInitialized) return;
        this._observerInitialized = true;

        const heroEl = this.template.querySelector('[data-hero]');
        if (!heroEl) return;

        const io = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    heroEl.classList.add('in-view');
                    io.unobserve(heroEl);
                }
            });
        }, { threshold: 0.15 });

        io.observe(heroEl);
    }

    navigateToProjectRequest() {
        // Navigate to an external page (absolute URL)
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: this.registrationUrl
            }
        });
    }
}