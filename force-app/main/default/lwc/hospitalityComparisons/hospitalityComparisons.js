import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
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
    // Starting position shifted left to reveal 25% of the "After" image
    @track sliderPosition = 50; 

    isDragging = false;
    myTargetName = 'HospitalityComparisons'; 
    
  hasScrolled = false;
  urlTargetName = null;

  @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            // Grab the c__target value from the URL (e.g., ?c__target=beforeAfter)
            this.urlTargetName = currentPageReference.state?.c__target;
        }
    }

    categories = [
        { label: 'Hotels',   before: HOTEL_BEFORE,   after: HOTEL_AFTER },
        { label: 'Resorts',  before: RESORT_BEFORE,  after: RESORT_AFTER },
        { label: 'Boutique', before: BOUTIQUE_BEFORE,after: BOUTIQUE_AFTER },
        { label: 'Cafe',     before: CAFE_BEFORE,    after: CAFE_AFTER }
    ];

    /* Safely maps the active class to the current category for the HTML template */
    get displayCategories() {
        return this.categories.map(cat => ({
            ...cat,
            tabClass: cat.label === this.activeCategory ? 'ba-tab active' : 'ba-tab'
        }));
    }

    /* Selected category */
    get currentCategory() {
        return this.categories.find(c => c.label === this.activeCategory);
    }

    /* Caches all images so tabs load instantly */
    get preloadUrls() {
        let urls = [];
        this.categories.forEach(c => {
            urls.push(c.before);
            urls.push(c.after);
        });
        return urls;
    }

    /* LWC-safe inline styles using clip-path instead of width */
    get overlayStyle() {
        return `clip-path: polygon(0 0, ${this.sliderPosition}% 0, ${this.sliderPosition}% 100%, 0 100%); 
                -webkit-clip-path: polygon(0 0, ${this.sliderPosition}% 0, ${this.sliderPosition}% 100%, 0 100%);`;
    }

    get handleStyle() {
        return `left: ${this.sliderPosition}%`;
    }

    // --- Label Visibility Getters ---
    get afterLabelClass() {
        const baseClass = 'ba-label ba-label-left';
        return this.sliderPosition < 15 ? `${baseClass} hidden-label` : baseClass;
    }

    get beforeLabelClass() {
        const baseClass = 'ba-label ba-label-right';
        return this.sliderPosition > 85 ? `${baseClass} hidden-label` : baseClass;
    }

    renderedCallback() {
        if (this.urlTargetName === this.myTargetName && !this.hasScrolled) {
            this.hasScrolled = true; // Prevents it from scrolling every time you interact with the page

            // A small timeout ensures the rest of the Experience Cloud page has finished loading its layout
            setTimeout(() => {
                const elementToScrollTo = this.template.querySelector('.scroll-target');
                if (elementToScrollTo) {
                    elementToScrollTo.scrollIntoView({ 
                        behavior: 'smooth', 
                        block: 'start' 
                    });
                }
            }, 500); 
        }
    }
    /* Category switch */
    handleCategoryClick(event) {
        this.activeCategory = event.target.dataset.category;
        // Reset to default left offset when switching
        this.sliderPosition = 50;
    }

    /* Start dragging */
    startDrag(event) {
        event.preventDefault();
        this.isDragging = true;

        document.addEventListener('mousemove', this.onDrag);
        document.addEventListener('mouseup', this.stopDrag);

        document.addEventListener('touchmove', this.onDrag, { passive: false });
        document.addEventListener('touchend', this.stopDrag);
    }

    /* Drag handler */
    onDrag = (event) => {
        if (!this.isDragging) return;
        event.preventDefault(); 

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