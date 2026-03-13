import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSheetDetails from '@salesforce/apex/ExpenseSheetController.getSheetDetails';
import updateSheetStatus from '@salesforce/apex/ExpenseSheetController.updateSheetStatus';
import SITE_LABEL_URL from '@salesforce/label/c.Arelia_Site_Label'; 
import LightningConfirm from 'lightning/confirm';

export default class ExpenseApprovalUi extends LightningElement {
    recordId;
    @track sheet;
    @track isLoading = true;
    @track error;
    
    // UI States
    @track showSuccessModal = false;
    @track isProcessed = false;
    finalStatus = '';

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

    // --- APPROVE FLOW ---
    async handleApprove() {
        const result = await LightningConfirm.open({
            message: 'Are you sure you want to APPROVE this expense sheet?',
            variant: 'headerless',
            label: 'Confirm Approval',
            theme: 'success' 
        });

        if(result) {
            this.processAction('Approved');
        }
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
        window.location.href = SITE_LABEL_URL;
    }
}