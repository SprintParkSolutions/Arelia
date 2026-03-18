import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import LIVING_BEFORE from '@salesforce/resourceUrl/LivingRoomBefore';
import LIVING_AFTER  from '@salesforce/resourceUrl/LivingRoomAfter';
import BEDROOM_BEFORE from '@salesforce/resourceUrl/BedroomBefore';
import BEDROOM_AFTER  from '@salesforce/resourceUrl/BedroomAfter';
import KITCHEN_BEFORE from '@salesforce/resourceUrl/KitchenBefore';
import KITCHEN_AFTER  from '@salesforce/resourceUrl/KitchenAfter';
import BATH_BEFORE    from '@salesforce/resourceUrl/BathroomBefore';
import BATH_AFTER     from '@salesforce/resourceUrl/BathroomAfter';

export default class BeforeAfter extends LightningElement {
  @api beforeAlt = 'Before Renovation';
  @api afterAlt = 'After Renovation';

  @track pair = 'living';
  // Starts on the leftmost side (10% visible)
  @track position = 50; 
  dragging = false;
  myTargetName = 'beforeAfter'; 
    
  hasScrolled = false;
  urlTargetName = null;

  @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            // Grab the c__target value from the URL (e.g., ?c__target=beforeAfter)
            this.urlTargetName = currentPageReference.state?.c__target;
        }
    }

  presets = {
    living:  { before: LIVING_BEFORE,  after: LIVING_AFTER },
    bedroom: { before: BEDROOM_BEFORE, after: BEDROOM_AFTER },
    kitchen: { before: KITCHEN_BEFORE, after: KITCHEN_AFTER },
    bath:    { before: BATH_BEFORE,    after: BATH_AFTER }
  };

  get computedBefore() {
    return (this.presets[this.pair] && this.presets[this.pair].before) || LIVING_BEFORE;
  }
  get computedAfter() {
    return (this.presets[this.pair] && this.presets[this.pair].after) || LIVING_AFTER;
  }
  // The AFTER label is on the left. Hide it if the slider goes below 15%
  get afterLabelClass() {
      const baseClass = 'ba-label ba-label-after';
      return this.position < 15 ? `${baseClass} hidden-label` : baseClass;
  }
  // The BEFORE label is on the right. Hide it if the slider goes above 85%
  get beforeLabelClass() {
      const baseClass = 'ba-label ba-label-before';
      return this.position > 85 ? `${baseClass} hidden-label` : baseClass;
  }
  // Creates an array of all image URLs to force the browser to preload them
  get preloadUrls() {
    return [
        LIVING_BEFORE, LIVING_AFTER,
        BEDROOM_BEFORE, BEDROOM_AFTER,
        KITCHEN_BEFORE, KITCHEN_AFTER,
        BATH_BEFORE, BATH_AFTER
    ];
  }

  // Uses CSS clip-path to act as a mask, completely eliminating image zooming/squishing
  get overlayStyle() {
    return `clip-path: polygon(0 0, ${this.position}% 0, ${this.position}% 100%, 0 100%); 
            -webkit-clip-path: polygon(0 0, ${this.position}% 0, ${this.position}% 100%, 0 100%);`;
  }
  
  get handleStyle() {
    return `left: ${this.position}%;`;
  }

  get livingTabClass() { return this.pair === 'living' ? 'ba-tab active' : 'ba-tab'; }
  get bedroomTabClass() { return this.pair === 'bedroom' ? 'ba-tab active' : 'ba-tab'; }
  get kitchenTabClass() { return this.pair === 'kitchen' ? 'ba-tab active' : 'ba-tab'; }
  get bathTabClass() { return this.pair === 'bath' ? 'ba-tab active' : 'ba-tab'; }

  get isSelectedLiving() { return String(this.pair === 'living'); }
  get isSelectedBedroom() { return String(this.pair === 'bedroom'); }
  get isSelectedKitchen() { return String(this.pair === 'kitchen'); }
  get isSelectedBath() { return String(this.pair === 'bath'); }

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
  
  onSelectPair(evt) {
    const key = evt.currentTarget.dataset.pair;
    if (key) {
        this.pair = key;
        // Resets the slider to the leftmost side when switching tabs
        this.position = 50; 
    }
  }

  /* Start dragging */
  /* Start dragging */
  /* Start dragging */
    startDrag(event) {
        event.preventDefault();
        this.dragging = true;

        document.addEventListener('mousemove', this.onDrag);
        document.addEventListener('mouseup', this.stopDrag);

        document.addEventListener('touchmove', this.onDrag, { passive: false });
        document.addEventListener('touchend', this.stopDrag);
    }

    /* Drag handler */
    onDrag = (event) => {
        if (!this.dragging) return;
        event.preventDefault(); 

        const stage = this.template.querySelector('[data-id="stage"]');
        if (!stage) return;
        
        const rect = stage.getBoundingClientRect();

        const clientX = event.touches
            ? event.touches[0].clientX
            : event.clientX;

        let percent = ((clientX - rect.left) / rect.width) * 100;
        percent = Math.max(0, Math.min(100, percent));

        this.position = percent;
    };

    /* Stop dragging */
    stopDrag = () => {
        this.dragging = false;

        document.removeEventListener('mousemove', this.onDrag);
        document.removeEventListener('mouseup', this.stopDrag);

        document.removeEventListener('touchmove', this.onDrag);
        document.removeEventListener('touchend', this.stopDrag);
    };

  handleKeyDown(e) {
    const step = 5;
    if (e.key === 'ArrowLeft') {
        this.position = Math.max(0, this.position - step);
    } else if (e.key === 'ArrowRight') {
        this.position = Math.min(100, this.position + step);
    }
  }
}