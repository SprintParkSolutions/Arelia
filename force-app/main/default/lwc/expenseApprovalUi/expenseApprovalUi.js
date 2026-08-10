import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSheetDetails from '@salesforce/apex/ExpenseSheetController.getSheetDetails';
import updateSheetStatus from '@salesforce/apex/ExpenseSheetController.updateSheetStatus';
import Arelia_Site_Redirect_URL_Label from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label'; 

export default class ExpenseApprovalUi extends LightningElement {
    recordId;
    @track sheet;
    @track isLoading = true;
    @track error;
    
    // UI States
    @track showSuccessModal = false;
    @track isProcessed = false;
    finalStatus = '';

    // Custom Confirmation Modal Variables
    @track showConfirmModal = false;
    @track confirmMessage = '';
    @track confirmTitle = '';

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference && currentPageReference.state) {
            this.recordId = currentPageReference.state.c__recordId || currentPageReference.state.id;
            
            if(this.recordId) {
                this.loadData();
            } else {
                this.error = 'No Record ID found in URL. Please check your email link.';
                this.isLoading = false;
            }
        }
    }

    loadData() {
        getSheetDetails({ sheetId: this.recordId })
            .then(result => {
                this.sheet = result;
                if(this.sheet.Status__c !== 'Submitted') {
                    this.isProcessed = true;
                    this.finalStatus = this.sheet.Status__c;
                }
                this.isLoading = false;
            })
            .catch(err => {
                this.error = 'Error loading sheet: ' + (err.body ? err.body.message : err.message);
                this.isLoading = false;
            });
    }

    // --- APPROVE FLOW (CUSTOM MODAL) ---
    handleApprove() {
        this.confirmTitle = 'Confirm Approval';
        this.confirmMessage = 'Are you sure you want to APPROVE this expense sheet?';
        this.showConfirmModal = true;
    }

    handleConfirmCancel() {
        this.showConfirmModal = false;
    }

    handleConfirmProceed() {
        this.showConfirmModal = false;
        this.processAction('Approved');
    }

    processAction(status) {
        this.isLoading = true;
        updateSheetStatus({ sheetId: this.recordId, status: status, reason: null })
            .then(() => {
                this.finalStatus = status;
                this.isProcessed = true;
                this.showSuccessModal = true;
            })
            .catch(err => {
                this.error = 'Update failed: ' + (err.body ? err.body.message : err.message);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleFinalClose() {
        const redirectUrl = (Arelia_Site_Redirect_URL_Label || '').trim();
        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }
}