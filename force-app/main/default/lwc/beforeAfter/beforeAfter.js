import { LightningElement, api, track } from 'lwc';

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
  @track position = 50; 
  dragging = false;

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
  
  // Controls the width of the left (Before) overlay
  get overlayStyle() {
    return `width: ${this.position}%;`;
  }
  
  // Controls handle horizontal position
  get handleStyle() {
    return `left: ${this.position}%;`;
  }

  // --- Tab Getters ---
  get livingTabClass() { return this.pair === 'living' ? 'ba-tab active' : 'ba-tab'; }
  get bedroomTabClass() { return this.pair === 'bedroom' ? 'ba-tab active' : 'ba-tab'; }
  get kitchenTabClass() { return this.pair === 'kitchen' ? 'ba-tab active' : 'ba-tab'; }
  get bathTabClass() { return this.pair === 'bath' ? 'ba-tab active' : 'ba-tab'; }

  get isSelectedLiving() { return String(this.pair === 'living'); }
  get isSelectedBedroom() { return String(this.pair === 'bedroom'); }
  get isSelectedKitchen() { return String(this.pair === 'kitchen'); }
  get isSelectedBath() { return String(this.pair === 'bath'); }

  // --- Room tab handler ---
  onSelectPair(evt) {
    const key = evt.currentTarget.dataset.pair;
    if (key) {
        this.pair = key;
        this.position = 50; // reset slider to center on tab change
    }
  }

  // --- Drag logic ---
  handlePointerDown(evt) {
    evt.preventDefault();
    this.dragging = true;
    
    this._boundMove = this._onMove.bind(this);
    this._boundUp = this._onUp.bind(this);

    window.addEventListener('pointermove', this._boundMove, { passive: false });
    window.addEventListener('pointerup', this._boundUp, { passive: false });
    window.addEventListener('pointercancel', this._boundUp, { passive: false });
    
    window.addEventListener('touchmove', this._boundMove, { passive: false });
    window.addEventListener('touchend', this._boundUp, { passive: false });
    
    const clientX = this._extractClientX(evt);
    this._updatePosition(clientX);
  }

  _onMove(e) {
    if (!this.dragging) return;
    e.preventDefault();
    const clientX = this._extractClientX(e);
    this._updatePosition(clientX);
  }

  _onUp(e) {
    this.dragging = false;
    window.removeEventListener('pointermove', this._boundMove);
    window.removeEventListener('pointerup', this._boundUp);
    window.removeEventListener('pointercancel', this._boundUp);
    window.removeEventListener('touchmove', this._boundMove);
    window.removeEventListener('touchend', this._boundUp);
  }

  _extractClientX(evt) {
    if (evt.touches && evt.touches[0]) return evt.touches[0].clientX;
    if (evt.changedTouches && evt.changedTouches[0]) return evt.changedTouches[0].clientX;
    return evt.clientX;
  }

  _updatePosition(clientX) {
    const stage = this.template.querySelector('[data-id="stage"]');
    if (!stage) return;
    
    const rect = stage.getBoundingClientRect();
    let pct = ((clientX - rect.left) / rect.width) * 100;
    pct = Math.max(0, Math.min(100, pct));
    this.position = pct;
  }

  handleKeyDown(e) {
    const step = 5;
    if (e.key === 'ArrowLeft') {
        this.position = Math.max(0, this.position - step);
    } else if (e.key === 'ArrowRight') {
        this.position = Math.min(100, this.position + step);
    }
  }
}