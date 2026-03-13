import { LightningElement, api, track } from 'lwc';
import getLatestSVR from '@salesforce/apex/SVRWizardController.getLatestSVR';
import createSVR from '@salesforce/apex/SVRWizardController.createSVR';
import saveStep from '@salesforce/apex/SVRWizardController.saveStep';
import markBlueprintUploaded from '@salesforce/apex/SVRWizardController.markBlueprintUploaded';
import finalSubmit from '@salesforce/apex/SVRWizardController.finalSubmit';
import getFieldSetFields from '@salesforce/apex/SVRWizardController.getFieldSetFields';
import getFiles from '@salesforce/apex/SVRWizardController.getFiles';
import LightningConfirm from 'lightning/confirm';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from "lightning/actions";

export default class SiteVisitReportWizard extends LightningElement {
    @api recordId; 
    @api objectApiName; 

    @track svrId;
    @track currentView = 'LOADING'; 
    @track step = 2; 
    
    @track isFinalSubmitted = false; 
    @track isManagerApproved = false; 

    @track step1EditableFields = []; 
    @track combinedPreviewFields = []; 
    @track files = [];

    // Internal Flag to track if we are in the middle of a Final Submit
    _pendingFinalSubmit = false;

    FIELDSET_STEP1 = 'SVR_Step1_Editable'; 
    FIELDSET_PREVIEW = 'SVR_Preview_Fields';

    async connectedCallback() {
        try {
            this.step1EditableFields = await getFieldSetFields({
                objectApi: 'Site_Visit_Report__c',
                fieldSetName: this.FIELDSET_STEP1
            });

            const svr = await getLatestSVR({ 
                parentId: this.recordId, 
                objectApiName: this.objectApiName 
            });

            if (svr && svr.Id) {
                this.svrId = svr.Id;
                this.isFinalSubmitted = svr.Is_Final_Submitted__c;
                this.isManagerApproved = svr.Management_Approval__c; 
                this.currentView = 'LANDING';
            } else {
                this.currentView = 'CREATE';
            }

        } catch (error) {
            console.error(error);
            this.showToast('Error', 'Error initializing component', 'error');
        }
    }

    get currentStepString() {
        if (this.currentView === 'CREATE') return "1";
        if (this.currentView === 'WIZARD') return this.step.toString();
        return "1";
    }

    handleStartWizard() {
        this.currentView = 'WIZARD';
        if (this.isFinalSubmitted) {
            this.step = 3;
            this.prepareStep3();
        } else {
            this.step = 2;
        }
    }

    /* ========== CREATE ========== */
    async handleCreateSubmit(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        this.currentView = 'LOADING';

        try {
            this.svrId = await createSVR({
                parentId: this.recordId,
                objectApiName: this.objectApiName,
                draftData: fields
            });
            this.handleStartWizard();
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
            this.currentView = 'CREATE';
        }
    }

    /* ========== UPLOAD ========== */
    async handleUploadFinished() {
        try {
            await markBlueprintUploaded({ svrId: this.svrId });
            this.showToast('Success', 'Blueprint uploaded & verified', 'success');
        } catch (error) {
            console.error(error);
            this.showToast('Warning', 'File uploaded but checkbox update failed', 'warning');
        }
    }

    async goToStep3() {
        this.currentView = 'LOADING';
        await saveStep({ svrId: this.svrId, stepNo: 3 });
        await this.prepareStep3();
        this.step = 3;
        this.currentView = 'WIZARD';
    }

    async goBackToStep2() {
        this.step = 2;
    }

    /* ========== PREVIEW ========== */
    async prepareStep3() {
        const previewFieldNames = await getFieldSetFields({
            objectApi: 'Site_Visit_Report__c',
            fieldSetName: this.FIELDSET_PREVIEW
        });

        let combined = [];
        this.step1EditableFields.forEach(f => {
            combined.push({ apiName: f, isEditable: true, uniqueKey: f + '_edit' });
        });
        previewFieldNames.forEach(f => {
            if (!this.step1EditableFields.includes(f)) {
                combined.push({ apiName: f, isEditable: false, uniqueKey: f + '_read' });
            }
        });
        this.combinedPreviewFields = combined;

        const rawFiles = await getFiles({ recordId: this.svrId });
        this.files = rawFiles.map(file => {
            return {
                ...file,
                imageUrl: `/sfc/servlet.shepherd/document/download/${file.ContentDocumentId}`,
                isImage: ['JPG', 'JPEG', 'PNG', 'GIF'].includes(file.ContentDocument.FileType)
            };
        });
    }

    /* ========== BUTTON ACTIONS ========== */
    
    // 1. SAVE DRAFT CLICK
    async handleDraftSave() {
        this._pendingFinalSubmit = false; // Ensure flag is off
        const btn = this.template.querySelector('.hidden-submit-btn');
        if(btn) btn.click();
    }

    // 2. FINAL SUBMIT CLICK
    async submitFinal() {
        const ok = await LightningConfirm.open({
            label: 'Submit for Approval',
            message: 'Are you sure you want to submit this Site Visit Report for approval? You will not be able to make further edits once submitted.',
            theme: 'warning'
        });
        if (!ok) return;

        this.currentView = 'LOADING';
        
        // CRITICAL CHANGE: Set flag and trigger FORM save first.
        // We do NOT call Apex here. We wait for the form to save successfully.
        this._pendingFinalSubmit = true; 
        
        const btn = this.template.querySelector('.hidden-submit-btn');
        if(btn) btn.click();
    }

    // 3. FORM SUCCESS HANDLER (Handles both Draft & Final logic)
    async handleDraftSuccess() {
        
        // CASE A: User clicked "Final Submit"
        if (this._pendingFinalSubmit) {
            try {
                // The form is now saved. The record is updated.
                // NOW it is safe to change the status to 'Approved'
                await finalSubmit({ svrId: this.svrId });
                
                this.isFinalSubmitted = true;
                this.showToast('Success', 'Submitted for Approval Successfully', 'success');
                this.closeQuickAction();
                
            } catch (error) {
                this.showToast('Error', error.body.message, 'error');
                this.currentView = 'WIZARD';
            } finally {
                this._pendingFinalSubmit = false; // Reset flag
            }
        } 
        // CASE B: User clicked "Save Draft"
        else {
            this.showToast('Saved', 'Draft saved locally.', 'success');
        }
    }
    
    // 4. FORM ERROR HANDLER (New)
    handleDraftError(event) {
        this.currentView = 'WIZARD';
        this._pendingFinalSubmit = false; // Reset flag so we don't get stuck
        this.showToast('Error', 'Error saving record details: ' + event.detail.message, 'error');
    }

    /* ========== GETTERS ========== */
    get isLoading() { return this.currentView === 'LOADING'; }
    get isCreateView() { return this.currentView === 'CREATE'; }
    get isLandingView() { return this.currentView === 'LANDING'; }
    get isWizardView() { return this.currentView === 'WIZARD'; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get isReadOnly() { return this.isManagerApproved; }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}