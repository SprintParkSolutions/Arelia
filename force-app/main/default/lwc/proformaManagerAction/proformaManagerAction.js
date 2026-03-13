import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import ARELIA_SITE_URL from '@salesforce/label/c.Arelia_Site_Label';
import getInvoice from '@salesforce/apex/ProformaManagerController.getInvoiceById';
import submitDecision from '@salesforce/apex/ProformaManagerController.submitManagerDecision';

export default class ProformaManagerAction extends LightningElement {
    @track invoiceData;
    @track comments = '';
    @track isLoading = true;
    @track error;
    
    @track showCommentBox = false;
    
    // Modal States
    @track showConfirmationModal = false;
    @track showSuccessModal = false;
    @track confirmationMessage = '';
    @track successMessage = '';
    
    // Internal variable to store which action is being confirmed
    pendingAction;

    recordId; 

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.id;
            this.loadData();
        }
    }

    loadData() {
        if (!this.recordId) {
            this.error = 'Invalid Link: Record ID missing.';
            this.isLoading = false;
            return;
        }

        getInvoice({ recordId: this.recordId })
            .then(result => {
                this.invoiceData = result;
                this.comments = result.comments || '';
                this.isLoading = false;
            })
            .catch(error => {
                console.error(error);
                this.error = 'Record Not Found or Access Denied.';
                this.isLoading = false;
            });
    }

    get isLocked() {
        return this.invoiceData && 
              (this.invoiceData.managerStatus === 'Approved' || 
               this.invoiceData.managerStatus === 'Rejected');
    }

    get managerStatusDisplay() {
        if (this.invoiceData) {
            return this.invoiceData.managerStatus;
        }
        return 'Loading...';
    }
    
    get statusBadgeClass() {
        if (!this.invoiceData) return '';
        return this.invoiceData.managerStatus === 'Approved' 
            ? 'slds-badge slds-theme_success' 
            : 'slds-badge slds-theme_error';
    }

    handleCommentChange(event) { this.comments = event.target.value; }
    
    toggleComments() { this.showCommentBox = !this.showCommentBox; }

    // --- STEP 1: INITIAL CLICK HANDLERS ---

    // User clicks "Final Sign-Off"
    handleApproveClick() {
        if(this.showCommentBox) {
            this.showCommentBox = false;
        }
        
        this.pendingAction = 'Approve';
        this.confirmationMessage = 'Are you sure you want to approve this invoice for final sign-off?';
        this.showConfirmationModal = true;
    }
    
    // User clicks "Submit Decision" (Reject)
    handleSubmitRejectionClick() {
        if(!this.comments) {
            const inputField = this.template.querySelector('lightning-textarea');
            inputField.setCustomValidity('Please provide a reason for rejection.');
            inputField.reportValidity();
            return;
        }
        
        this.pendingAction = 'Reject';
        this.confirmationMessage = 'Are you sure you want to reject this invoice and request changes?';
        this.showConfirmationModal = true;
    }

    // --- STEP 2: CONFIRMATION MODAL HANDLERS ---

    closeConfirmationModal() {
        this.showConfirmationModal = false;
        this.pendingAction = null;
    }

    handleConfirmYes() {
        this.showConfirmationModal = false;
        if(this.pendingAction) {
            this.submit(this.pendingAction);
        }
    }

    // --- STEP 3: API SUBMISSION ---

    submit(action) {
        this.isLoading = true;
        this.error = null;

        submitDecision({ recordId: this.recordId, action: action, comments: this.comments })
            .then(() => {
                this.isLoading = false;
                
                // Update Local State to 'lock' the UI visually behind the modal
                let newData = { ...this.invoiceData };
                newData.managerStatus = (action === 'Approve') ? 'Approved' : 'Rejected';
                this.invoiceData = newData;
                
                this.showCommentBox = false;
                
                // Prepare Success Message
                if(action === 'Approve') {
                    this.successMessage = 'The invoice has been successfully approved and signed off.';
                } else {
                    this.successMessage = 'The invoice has been rejected. Revision requests have been sent.';
                }

                // Show Success Modal
                this.showSuccessModal = true;
            })
            .catch(error => {
                console.error(error);
                this.error = error.body ? error.body.message : 'Unknown Error';
                this.isLoading = false;
            });
    }

    // --- STEP 4: SUCCESS MODAL CLOSE (REDIRECT) ---

    handleSuccessClose() {
        window.location.href = ARELIA_SITE_URL;
    }
}