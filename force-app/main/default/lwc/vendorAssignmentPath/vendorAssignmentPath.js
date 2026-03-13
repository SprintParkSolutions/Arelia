import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getPathStatus from '@salesforce/apex/VendorPathController.getPathStatus';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

const STEP_ORDER = [
    'Vendor Assigned', 
    'Vendor Work Started', 
    'Ongoing Tasks', 
    'Abscond', 
    'Vendor Work Completed'
];

export default class VendorAssignmentPath extends LightningElement {
    @api recordId; 
    @track effectiveId; // Holds the ID from either Builder or URL
    
    @track steps = [];
    @track currentStageName = '';
    @track isVisible = false; // Default to hidden until data arrives
    
    wiredPathResult;

    // 1. Get ID from URL if Builder binding fails
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (pageRef) {
            const urlId = pageRef.attributes.recordId || pageRef.state.recordId;
            
            if (this.recordId) {
                this.effectiveId = this.recordId;
            } else if (urlId) {
                this.effectiveId = urlId;
            }
        }
    }

    // 2. Fetch Status from Apex using effectiveId
    @wire(getPathStatus, { recordId: '$effectiveId' })
    wiredPath(result) {
        this.wiredPathResult = result;
        const { data, error } = result;

        if (data) {
            this.currentStageName = data;
            this.isVisible = true; 
            this.buildSteps();
        } else if (data === null) {
            this.isVisible = false; 
        } else if (error) {
            console.error('Error in VendorPath:', error);
            this.isVisible = false;
        }
    }

    // 3. Auto-Refresh on Record Change
    @wire(getRecord, { recordId: '$effectiveId', layoutTypes: ['Full'] })
    recordChange({ data }) {
        if (data) {
            refreshApex(this.wiredPathResult);
        }
    }

    buildSteps() {
        let activeIndex = STEP_ORDER.indexOf(this.currentStageName);
        if (activeIndex === -1) activeIndex = 0; 

        this.steps = STEP_ORDER.map((stepLabel, index) => {
            let className = 'slds-path__item';
            let isSelected = false;

            if (this.currentStageName === 'Vendor Work Completed' && index === activeIndex) {
                className += ' slds-is-won slds-is-active';
                isSelected = true;
            } else if (index < activeIndex) {
                className += ' slds-is-complete';
            } else if (index === activeIndex) {
                className += ' slds-is-current slds-is-active';
                isSelected = true;
            } else {
                className += ' slds-is-incomplete';
            }

            return { label: stepLabel, class: className, selected: isSelected };
        });
    }
}