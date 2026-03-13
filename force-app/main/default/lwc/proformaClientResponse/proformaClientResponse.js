import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import ARELIA_SITE_URL from '@salesforce/label/c.Arelia_Site_Label';
import getInvoice from '@salesforce/apex/ProformaInvoiceController.getInvoiceById';
import submitDecision from '@salesforce/apex/ProformaInvoiceController.submitClientDecision';

export default class ProformaClientResponse extends LightningElement {
    @track invoiceData;
    @track comments = '';
    @track isLoading = true;
    @track isSubmitted = false;
    @track error;
    
    // Toggle for comment box visibility
    @track showCommentBox = false;
    
    recordId; 

    // Modal States
    @track showConfirmationModal = false;
    @track showSuccessModal = false;
    @track confirmationMessage = '';
    @track successMessage = '';
    
    // Internal variable to store which action is being confirmed
    pendingStatus; 

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.id;
            this.loadInvoice();
        }
    }

    loadInvoice() {
        if (!this.recordId) {
            this.error = 'Invalid Link: Record ID missing.';
            this.isLoading = false;
            return;
        }

        getInvoice({ recordId: this.recordId })
            .then(result => {
                this.invoiceData = result;
                if (result.status === 'Approved' || result.status === 'Changes Requested') {
                    this.isSubmitted = true;
                }
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading invoice:', error);
                this.error = 'Invalid Link or Record Not Found.';
                this.isLoading = false;
            });
    }

    get statusBadgeClass() {
        if (!this.invoiceData) return 'slds-badge';
        if(this.invoiceData.status === 'Approved') return 'slds-badge slds-theme_success';
        if(this.invoiceData.status === 'Changes Requested') return 'slds-badge slds-theme_error';
        return 'slds-badge';
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
        if (this.error) this.error = null;
    }

    // Toggle the comment box (Request Changes)
    handleReject() {
        this.showCommentBox = !this.showCommentBox;
    }

    // --- STEP 1: INITIAL CLICK HANDLERS ---

    // User clicks "Approve Invoice"
    handleApproveClick() {
        // If comments box was open (changed mind), close it
        if(this.showCommentBox) {
            this.showCommentBox = false;
        }

        // Set pending action
        this.pendingStatus = 'Approved';
        this.confirmationMessage = 'Are you sure you want to approve this invoice?';
        this.showConfirmationModal = true;
    }

    // User clicks "Submit Changes" inside the comment box
    handleSubmitChangesClick() {
        if (!this.comments) {
            const inputField = this.template.querySelector('lightning-textarea');
            inputField.setCustomValidity('Please provide comments before requesting changes.');
            inputField.reportValidity();
            return;
        }

        // Set pending action
        this.pendingStatus = 'Changes Requested';
        this.confirmationMessage = 'Are you sure you want to submit these changes?';
        this.showConfirmationModal = true;
    }

    // --- STEP 2: CONFIRMATION MODAL HANDLERS ---

    closeConfirmationModal() {
        this.showConfirmationModal = false;
        this.pendingStatus = null;
    }

    handleConfirmYes() {
        this.showConfirmationModal = false;
        if(this.pendingStatus) {
            this.submit(this.pendingStatus);
        }
    }

    // --- STEP 3: API SUBMISSION ---

    submit(status) {
        this.isLoading = true;
        this.error = null;

        submitDecision({ recordId: this.recordId, status: status, comments: this.comments })
            .then(() => {   
                this.isLoading = false;
                this.isSubmitted = true;
                this.invoiceData = { ...this.invoiceData, status: status, comments: this.comments };
                
                // Hide inputs
                this.showCommentBox = false;
                
                // Prepare Success Message
                if(status === 'Approved') {
                    this.successMessage = 'The invoice has been successfully approved.';
                } else {
                    this.successMessage = 'Your revision request has been submitted successfully.';
                }

                // Show Success Modal
                this.showSuccessModal = true;
            })
            .catch(error => {
                console.error('Error submitting decision:', error);
                this.error = error.body ? error.body.message : 'Error submitting decision.';
                this.isLoading = false;
            });
    }

    // --- STEP 4: SUCCESS MODAL CLOSE (REDIRECT) ---

    handleSuccessClose() {
        window.location.href = ARELIA_SITE_URL;
    }
}