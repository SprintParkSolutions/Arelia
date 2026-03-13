import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getAllStages from '@salesforce/apex/AreliaPathController.getAllStages';
import getPathStatus from '@salesforce/apex/AreliaPathController.getPathStatus';

// Import fields
import CATALOGUE_LINK_SENT_FIELD from '@salesforce/schema/Opportunity.Catalogue_Link_Sent__c';

const FIELDS = [
    'Opportunity.StageName',
    'Opportunity.Catalogue_Link_Sent__c'
];

const CATALOGUE_STAGES = [
    'Catalogue Link Sent', 
    'Catalogue Received', 
    'Catalogue Manager Approval'
];

export default class AreliaPath extends LightningElement {
    @api 
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.effectiveRecordId = value;
            this.checkVisibility();
        }
    }
    _recordId;

    @track effectiveRecordId;
    @track steps = [];
    @track isReady = false;
    @track hasAccess = true;
    @track isVisible = true; 

    _allStages = [];
    _currentPathStatus; 
    _catalogueSent = false;
    wiredPathResult;
    
    // Flag to trigger scrolling only when steps change
    _stepsChanged = false;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (this._recordId) {
            this.effectiveRecordId = this._recordId;
            return;
        }
        const state = pageRef?.state || {};
        const fromState = state.recordId || state.id || state.c__recordId;

        if (fromState) {
            this.effectiveRecordId = fromState;
            this.checkVisibility();
            return;
        }

        try {
            const href = window.location.href;
            const url = new URL(href);
            const qp = url.searchParams.get('recordId') || url.searchParams.get('id');

            if (qp) {
                this.effectiveRecordId = qp;
            } else {
                const anyId = href.match(/([a-zA-Z0-9]{15,18})/);
                if (anyId?.[1]) {
                    this.effectiveRecordId = anyId[1];
                }
            }
            this.checkVisibility();
        } catch (e) {
            console.warn('Could not parse Record ID from URL', e);
        }
    }

    checkVisibility() {
        if (this.effectiveRecordId && String(this.effectiveRecordId).startsWith('006')) {
            this.isVisible = true;
        } else {
            this.isVisible = false;
        }
    }

    @wire(getAllStages)
    wiredStages({ error, data }) {
        if (data) {
            this._allStages = data;
            this.tryBuildSteps();
        } else if (error) {
            console.error('Error loading stage definitions:', error);
        }
    }

    @wire(getRecord, { recordId: '$effectiveRecordId', fields: FIELDS })
    wiredRecordWatcher({ error, data }) {
        if (data) {
            this._catalogueSent = getFieldValue(data, CATALOGUE_LINK_SENT_FIELD);
            refreshApex(this.wiredPathResult);
            this.tryBuildSteps();
        } else if (error) {
            console.error('Error loading record data', error);
        }
    }

    @wire(getPathStatus, { oppId: '$effectiveRecordId' })
    wiredPathStatus(result) {
        this.wiredPathResult = result;
        const { data, error } = result;

        if (!this.effectiveRecordId || !this.isVisible) return;

        if (data) {
            this.hasAccess = true;
            this.isReady = true;
            this._currentPathStatus = data;
            this.tryBuildSteps();
        } else if (error) {
            this.hasAccess = false;
            this.isReady = true;
            console.error('Error loading path status:', error);
        }
    }

    tryBuildSteps() {
        if (!this._allStages || this._allStages.length === 0 || !this._currentPathStatus) {
            return;
        }

        let visibleStages = [...this._allStages];
        const currentActiveValue = this._currentPathStatus;
        
        const exceptionStages = ['Negotiation/Review', 'Resumed'];
        if (exceptionStages.includes(currentActiveValue)) {
            visibleStages = this._allStages;
        } else {
            visibleStages = visibleStages.filter(stage => !exceptionStages.includes(stage.value));
        }

        if (!this._catalogueSent) {
            visibleStages = visibleStages.filter(stage => !CATALOGUE_STAGES.includes(stage.value));
        }

        const activeIndex = visibleStages.findIndex(s => s.value === currentActiveValue);
        const targetIndex = activeIndex === -1 ? 0 : activeIndex;

        this.steps = visibleStages.map((stage, index) => {
            return this.buildStepObject(stage.label, index, targetIndex);
        });

        // FLAG: Signal that we need to scroll after render
        this._stepsChanged = true;
    }

    buildStepObject(label, index, activeIndex) {
        let stepClass = 'slds-path__item';
        let icon = 'utility:check';

        if (index < activeIndex) {
            stepClass += ' slds-is-complete';
        } else if (index === activeIndex) {
            stepClass += ' slds-is-current slds-is-active';
        } else {
            stepClass += ' slds-is-incomplete';
        }

        return {
            key: `${index}-${label}`,
            label: label,
            class: stepClass,
            icon: icon
        };
    }

    handleRefresh() {
        refreshApex(this.wiredPathResult);
    }

    // --- NEW: SCROLL LOGIC ---
    renderedCallback() {
        if (this._stepsChanged && this.isReady) {
            this._stepsChanged = false; // Reset flag so we don't scroll constantly
            
            // Allow DOM to paint
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => {
                this.scrollToActiveStep();
            });
        }
    }

    scrollToActiveStep() {
        const container = this.template.querySelector('.slds-path__scroller');
        const activeItem = this.template.querySelector('.slds-is-current');

        if (container && activeItem) {
            // Calculate center position
            const containerWidth = container.offsetWidth;
            const itemLeft = activeItem.offsetLeft;
            const itemWidth = activeItem.offsetWidth;

            // Scroll to center the active item
            // Position = Item's Left Offset - (Half Container Width) + (Half Item Width)
            const scrollPos = itemLeft - (containerWidth / 2) + (itemWidth / 2);

            container.scrollTo({
                left: scrollPos,
                behavior: 'smooth'
            });
        }
    }
}