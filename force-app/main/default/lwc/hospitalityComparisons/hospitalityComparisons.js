import { LightningElement, track } from 'lwc';
// 1. Import individual Static Resources
import HOTEL_BEFORE from '@salesforce/resourceUrl/HotelBefore';
import HOTEL_AFTER  from '@salesforce/resourceUrl/HotelAfter';

import RESORT_BEFORE from '@salesforce/resourceUrl/ResortBefore';
import RESORT_AFTER  from '@salesforce/resourceUrl/ResortAfter';

import BOUTIQUE_BEFORE from '@salesforce/resourceUrl/BoutiqueBefore';
import BOUTIQUE_AFTER  from '@salesforce/resourceUrl/BoutiqueAfter';

import CAFE_BEFORE from '@salesforce/resourceUrl/CafeBefore';
import CAFE_AFTER  from '@salesforce/resourceUrl/CafeAfter'; 

export default class HospitalityComparisons extends LightningElement {
   @track activeCategory = 'Hotels';
    @track sliderPosition = 50; // %

    isDragging = false;

    categories = [
        { label: 'Hotels',   before: HOTEL_BEFORE,   after: HOTEL_AFTER },
        { label: 'Resorts',  before: RESORT_BEFORE,  after: RESORT_AFTER },
        { label: 'Boutique', before: BOUTIQUE_BEFORE,after: BOUTIQUE_AFTER },
        { label: 'Cafe',     before: CAFE_BEFORE,    after: CAFE_AFTER }
    ];

    /* Selected category */
    get currentCategory() {
        return this.categories.find(c => c.label === this.activeCategory);
    }

    /* LWC-safe inline styles */
    get beforeStyle() {
        return `width: ${this.sliderPosition}%`;
    }

    get handleStyle() {
        return `left: ${this.sliderPosition}%`;
    }

    /* Category switch */
    handleCategoryClick(event) {
        this.activeCategory = event.target.dataset.category;
        this.sliderPosition = 50;
    }

    /* Start dragging */
    startDrag(event) {
        event.preventDefault();
        this.isDragging = true;

        document.addEventListener('mousemove', this.onDrag);
        document.addEventListener('mouseup', this.stopDrag);

        // passive:false is CRITICAL to prevent mobile white overlay
        document.addEventListener('touchmove', this.onDrag, { passive: false });
        document.addEventListener('touchend', this.stopDrag);
    }

    /* Drag handler */
    onDrag = (event) => {
        if (!this.isDragging) return;

        event.preventDefault(); // stops browser overlay

        const container = this.template.querySelector('.ba-container');
        const rect = container.getBoundingClientRect();

        const clientX = event.touches
            ? event.touches[0].clientX
            : event.clientX;

        let percent = ((clientX - rect.left) / rect.width) * 100;
        percent = Math.max(0, Math.min(100, percent));

        this.sliderPosition = percent;
    };

    /* Stop dragging */
    stopDrag = () => {
        this.isDragging = false;

        document.removeEventListener('mousemove', this.onDrag);
        document.removeEventListener('mouseup', this.stopDrag);

        document.removeEventListener('touchmove', this.onDrag);
        document.removeEventListener('touchend', this.stopDrag);
    };
}