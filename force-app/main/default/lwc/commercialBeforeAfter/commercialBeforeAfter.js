import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
// STATIC RESOURCE IMPORTS
import RESTAURANT_BEFORE from '@salesforce/resourceUrl/RestaurantBefore';
import RESTAURANT_AFTER  from '@salesforce/resourceUrl/RestaurantAfter';

import BAR_BEFORE from '@salesforce/resourceUrl/BarBefore';
import BAR_AFTER  from '@salesforce/resourceUrl/BarAfter';

import BANQUET_BEFORE from '@salesforce/resourceUrl/BanquetBefore';
import BANQUET_AFTER  from '@salesforce/resourceUrl/BanquetAfter';

import LOBBY_BEFORE from '@salesforce/resourceUrl/LobbyBefore';
import LOBBY_AFTER  from '@salesforce/resourceUrl/LobbyAfter';

export default class CommercialBeforeAfter extends LightningElement {
  @api beforeImage;
  @api afterImage;

  @api beforeAlt = 'Before Image';
  @api afterAlt = 'After Image';

  @track pair = 'restaurant';

  // Set default starting position to 25%
  @track position = 50;

  dragging = false;
  myTargetName = 'CommercialBeforeAfter'; 
    
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
    restaurant: { before: RESTAURANT_BEFORE, after: RESTAURANT_AFTER },
    bar:        { before: BAR_BEFORE,        after: BAR_AFTER },
    banquet:    { before: BANQUET_BEFORE,    after: BANQUET_AFTER },
    lobby:      { before: LOBBY_BEFORE,      after: LOBBY_AFTER }
  };

  get computedBefore() {
    if (this.beforeImage) return this.beforeImage;
    return (this.presets[this.pair] && this.presets[this.pair].before) || RESTAURANT_BEFORE;
  }
  get computedAfter() {
    if (this.afterImage) return this.afterImage;
    return (this.presets[this.pair] && this.presets[this.pair].after) || RESTAURANT_AFTER;
  }

  // Caches all images so tabs load instantly
  get preloadUrls() {
    return [
        RESTAURANT_BEFORE, RESTAURANT_AFTER,
        BAR_BEFORE, BAR_AFTER,
        BANQUET_BEFORE, BANQUET_AFTER,
        LOBBY_BEFORE, LOBBY_AFTER
    ];
  }

  // Uses CSS clip-path to act as a mask
  get afterWrapStyle() {
    return `clip-path: polygon(0 0, ${this.position}% 0, ${this.position}% 100%, 0 100%); 
            -webkit-clip-path: polygon(0 0, ${this.position}% 0, ${this.position}% 100%, 0 100%);`;
  }

  // Handle position logic
  get handleStyle() {
    return `left: ${this.position}%;`;
  }

  // --- Label Visibility Getters ---
  get afterLabelClass() {
      const baseClass = 'ba-label ba-label-left';
      return this.position < 15 ? `${baseClass} hidden-label` : baseClass;
  }

  get beforeLabelClass() {
      const baseClass = 'ba-label ba-label-right';
      return this.position > 85 ? `${baseClass} hidden-label` : baseClass;
  }

  // tab class getters
  get restaurantTabClass() { return this.pair === 'restaurant' ? 'ba-tab active' : 'ba-tab'; }
  get barTabClass()        { return this.pair === 'bar' ? 'ba-tab active' : 'ba-tab'; }
  get banquetTabClass()    { return this.pair === 'banquet' ? 'ba-tab active' : 'ba-tab'; }
  get lobbyTabClass()      { return this.pair === 'lobby' ? 'ba-tab active' : 'ba-tab'; }

  // aria-selected getters
  get isSelectedRestaurant() { return String(this.pair === 'restaurant'); }
  get isSelectedBar()        { return String(this.pair === 'bar'); }
  get isSelectedBanquet()    { return String(this.pair === 'banquet'); }
  get isSelectedLobby()      { return String(this.pair === 'lobby'); }

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
    if (!key) return;
    this.pair = key;
    // reset slider to match default position when switching
    this.position = 50;
  }

  // -------------------------
  // Pointer / touch dragging
  // -------------------------
  // -------------------------
    // Standardized Pointer / touch dragging
    // -------------------------
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

        const stage = this.template.querySelector('.ba-stage');
        if (!stage) return;
        
        const rect = stage.getBoundingClientRect();

        const clientX = event.touches
            ? event.touches[0].clientX
            : event.clientX;

        let percent = ((clientX - rect.left) / rect.width) * 100;
        percent = Math.max(0, Math.min(100, percent));

        this.position = Math.round(percent);

        // Unique to Commercial component: Accessibility & Event firing
        const handle = this.template.querySelector('.ba-handle');
        if (handle) handle.setAttribute('aria-valuenow', String(this.position));
        this._dispatchChangedDebounced();
    };

    /* Stop dragging */
    stopDrag = () => {
        this.dragging = false;

        document.removeEventListener('mousemove', this.onDrag);
        document.removeEventListener('mouseup', this.stopDrag);

        document.removeEventListener('touchmove', this.onDrag);
        document.removeEventListener('touchend', this.stopDrag);

        // Emit final changed event on mouse up
        this.dispatchEvent(new CustomEvent('changed', { detail: { position: this.position }, bubbles: true, composed: true }));
    };

  // -------------------------
  // Keyboard support
  // -------------------------
  handleKeyDown(e) {
    let changed = false;
    const step = 3;
    if (e.key === 'ArrowLeft') {
      this.position = Math.max(0, this.position - step); changed = true;
    } else if (e.key === 'ArrowRight') {
      this.position = Math.min(100, this.position + step); changed = true;
    } else if (e.key === 'Home') {
      this.position = 0; changed = true;
    } else if (e.key === 'End') {
      this.position = 100; changed = true;
    }

    if (changed) {
      e.preventDefault();
      const handle = this.template.querySelector('.ba-handle');
      if (handle) handle.setAttribute('aria-valuenow', String(this.position));
      this._dispatchChangedDebounced();
    }
  }

  _dispatchChangedDebounced() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer);
    this._debounceTimer = setTimeout(() => {
      this.dispatchEvent(new CustomEvent('changed', { detail: { position: this.position }, bubbles: true, composed: true }));
    }, 80);
  }
}