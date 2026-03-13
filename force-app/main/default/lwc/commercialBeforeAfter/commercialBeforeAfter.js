import { LightningElement, api, track } from 'lwc';

// STATIC RESOURCE IMPORTS (replace with your actual static resource names)
import RESTAURANT_BEFORE from '@salesforce/resourceUrl/RestaurantBefore';
import RESTAURANT_AFTER  from '@salesforce/resourceUrl/RestaurantAfter';

import BAR_BEFORE from '@salesforce/resourceUrl/BarBefore';
import BAR_AFTER  from '@salesforce/resourceUrl/BarAfter';

import BANQUET_BEFORE from '@salesforce/resourceUrl/BanquetBefore';
import BANQUET_AFTER  from '@salesforce/resourceUrl/BanquetAfter';

import LOBBY_BEFORE from '@salesforce/resourceUrl/LobbyBefore';
import LOBBY_AFTER  from '@salesforce/resourceUrl/LobbyAfter';

export default class CommercialBeforeAfter extends LightningElement {
  // optional explicit overrides from parent
  @api beforeImage;
  @api afterImage;

  @api beforeAlt = 'Before Image';
  @api afterAlt = 'After Image';

  // which preset is active (tracked so template updates)
  @track pair = 'restaurant';

  // slider position (0..100)
  @track position = 50;

  // dragging state
  dragging = false;

  // preset mapping
  presets = {
    restaurant: { before: RESTAURANT_AFTER, after: RESTAURANT_BEFORE },
  bar:        { before: BAR_AFTER,        after: BAR_BEFORE },
  banquet:    { before: BANQUET_AFTER,    after: BANQUET_BEFORE },
  lobby:      { before: LOBBY_AFTER,      after: LOBBY_BEFORE }
  };

  // -------------------------
  // Template getters
  // -------------------------
  get computedBefore() {
    if (this.beforeImage) return this.beforeImage;
    return (this.presets[this.pair] && this.presets[this.pair].before) || RESTAURANT_BEFORE;
  }
  get computedAfter() {
    if (this.afterImage) return this.afterImage;
    return (this.presets[this.pair] && this.presets[this.pair].after) || RESTAURANT_AFTER;
  }

  // This controls the width of the right-aligned overlay wrap
  get afterWrapStyle() {
    return `width: ${100 - this.position}%;`;
  }

  // This controls the position of the slider handle
  get handleStyle() {
    // Subtract half the handle width (18px) to center it
    return `left: calc(${this.position}% - 18px);`;
  }

  // tab class getters
  get restaurantTabClass() { return this.pair === 'restaurant' ? 'ba-tab active' : 'ba-tab'; }
  get barTabClass()       { return this.pair === 'bar' ? 'ba-tab active' : 'ba-tab'; }
  get banquetTabClass()   { return this.pair === 'banquet' ? 'ba-tab active' : 'ba-tab'; }
  get lobbyTabClass()     { return this.pair === 'lobby' ? 'ba-tab active' : 'ba-tab'; }

  // aria-selected getters
  get isSelectedRestaurant() { return this.pair === 'restaurant' ? 'true' : 'false'; }
  get isSelectedBar()        { return this.pair === 'bar' ? 'true' : 'false'; }
  get isSelectedBanquet()    { return this.pair === 'banquet' ? 'true' : 'false'; }
  get isSelectedLobby()      { return this.pair === 'lobby' ? 'true' : 'false'; }

  // -------------------------
  // Tab selection handler
  // -------------------------
  onSelectPair(evt) {
    const key = evt.currentTarget.dataset.pair;
    if (!key) return;
    this.pair = key;
    // reset slider center when switching
    this.position = 50;
  }

  // -------------------------
  // Pointer / touch dragging
  // -------------------------
  handlePointerDown(evt) {
    evt.preventDefault();
    this.dragging = true;

    if (!this._boundMove) {
      this._boundMove = this._onMove.bind(this);
      this._boundUp = this._onUp.bind(this);
    }

    window.addEventListener('pointermove', this._boundMove, { passive: false });
    window.addEventListener('pointerup', this._boundUp, { passive: false });
    window.addEventListener('pointercancel', this._boundUp, { passive: false });

    window.addEventListener('touchmove', this._boundMove, { passive: false });
    window.addEventListener('touchend', this._boundUp, { passive: false });
    window.addEventListener('touchcancel', this._boundUp, { passive: false });

    const clientX = this._extractClientX(evt);
    this._updatePositionFromClientX(clientX);
  }

  _onMove(e) {
    e.preventDefault();
    if (!this.dragging) return;
    const clientX = this._extractClientX(e);
    this._updatePositionFromClientX(clientX);
  }

  _onUp(e) {
    e.preventDefault();
    this.dragging = false;
    try {
      window.removeEventListener('pointermove', this._boundMove);
      window.removeEventListener('pointerup', this._boundUp);
      window.removeEventListener('pointercancel', this._boundUp);

      window.removeEventListener('touchmove', this._boundMove);
      window.removeEventListener('touchend', this._boundUp);
      window.removeEventListener('touchcancel', this._boundUp);
    } catch (err) { /* ignore */ }

    // emit final changed event
    this.dispatchEvent(new CustomEvent('changed', { detail: { position: this.position }, bubbles: true, composed: true }));
  }

  _extractClientX(evt) {
    if (!evt) return 0;
    if (evt.touches && evt.touches[0]) return evt.touches[0].clientX;
    if (evt.changedTouches && evt.changedTouches[0]) return evt.changedTouches[0].clientX;
    return evt.clientX || evt.pageX || 0;
  }

  _updatePositionFromClientX(clientX) {
    if (typeof clientX !== 'number') return;
    const stage = this.template.querySelector('.ba-stage');
    if (!stage) return;
    const rect = stage.getBoundingClientRect();
    let pct = ((clientX - rect.left) / rect.width) * 100;
    pct = Math.max(0, Math.min(100, pct));
    this.position = Math.round(pct);

    const handle = this.template.querySelector('.ba-handle');
    if (handle) handle.setAttribute('aria-valuenow', String(this.position));

    this._dispatchChangedDebounced();
  }

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