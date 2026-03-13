import { LightningElement } from 'lwc';
// Import Project Images
import PROJ_1 from '@salesforce/resourceUrl/Project1';
import PROJ_2 from '@salesforce/resourceUrl/Project2';
import PROJ_3 from '@salesforce/resourceUrl/Project3';
// Import the Texture Background
import BG_TEXTURE from '@salesforce/resourceUrl/LuxuryTexture';

export default class LuxuryPortfolio extends LightningElement {
    project1 = PROJ_1;
    project2 = PROJ_2;
    project3 = PROJ_3;

    // Create the background style string
    get backgroundStyle() {
        return `
            background-image: url(${BG_TEXTURE});
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
        `;
    }

    hasRendered = false;
    renderedCallback() {
        if (this.hasRendered) return;
        this.hasRendered = true;

        const cards = this.template.querySelectorAll('.project-card');
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('is-visible');
                    observer.unobserve(entry.target);
                }
            });
        }, { threshold: 0.2 });

        cards.forEach(card => observer.observe(card));
    }
}