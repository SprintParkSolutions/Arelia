import { LightningElement, api, wire, track } from 'lwc';
import getCurrentStage from '@salesforce/apex/ProjectPathController.getCurrentStage';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

const STEP_ORDER = [
    'Project Initiated', 'Project Started', 'Assign Vendor Assignments', 
    'Project Ongoing', 'Hold', 'Project Completion'
];

export default class ProjectCustomPath extends LightningElement {
    @api recordId;
    @track steps = [];
    currentStageName = '';
    isVisible = false; // Default to invisible
    
    wiredStageResult;

    @wire(getCurrentStage, { projectId: '$recordId' })
    wiredStage(result) {
        this.wiredStageResult = result;
        const { error, data } = result;
        
        if (data) {
            this.currentStageName = data;
            this.isVisible = true; // Show component only if we get valid data
            this.buildSteps();
        } else if (data === null) {
            // Apex returned null (wrong page or not a project)
            this.isVisible = false; 
        } else if (error) {
            this.isVisible = false;
            console.error('Error fetching path stage', error);
        }
    }

    @wire(getRecord, { recordId: '$recordId', layoutTypes: ['Full'] })
    recordChange({ data }) {
        if (data) {
            refreshApex(this.wiredStageResult);
        }
    }

    buildSteps() {
        let activeIndex = STEP_ORDER.indexOf(this.currentStageName);
        if (activeIndex === -1) activeIndex = 0; 

        this.steps = STEP_ORDER.map((stepLabel, index) => {
            let className = 'slds-path__item';
            let isSelected = false;

            // --- SPECIAL CASE: Final Stage (Project Completion) ---
            if (this.currentStageName === 'Project Completion' && index === activeIndex) {
                // Apply 'slds-is-won' to make it GREEN
                // Apply 'slds-is-active' to keep the arrow shape
                className += ' slds-is-won slds-is-active';
                isSelected = true;
            }
            // --- STANDARD LOGIC ---
            else if (index < activeIndex) {
                // Past steps are completed
                className += ' slds-is-complete';
            } 
            else if (index === activeIndex) {
                // Current step (not final) is Blue
                className += ' slds-is-current slds-is-active';
                isSelected = true;
            } 
            else {
                // Future steps
                className += ' slds-is-incomplete';
            }

            return {
                label: stepLabel,
                class: className,
                selected: isSelected
            };
        });
    }
}