import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import ARELIA_SITE_URL from '@salesforce/label/c.Arelia_Site_Label'; 
import getFileByToken from '@salesforce/apex/ImageApprovalController.getFileByToken';
import submitDecision from '@salesforce/apex/ImageApprovalController.submitDecision';

export default class PublicImageApproval extends LightningElement {
    @track fileData;
    token;
    error;
    
    // Form Inputs
    comments = '';
    showCommentBox = false;
    
    // Logic States
    isFinalized = false;
    @track isLoading = false; 

    // Modal States
    @track showConfirmationModal = false;
    @track showSuccessModal = false;
    @track confirmationMessage = '';
    @track successMessage = '';
    
    // Internal variable to store which action is being confirmed ('Approved' or 'Changes Requested')
    pendingStatus; 
   
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.token = currentPageReference.state.token;
            if (this.token) {
                this.loadData();
            } else {
                this.error = 'Invalid Link: Token missing.';
            }
        }
    }

    loadData() {
        getFileByToken({ token: this.token }) 
            .then(data => {
                this.fileData = data;
                if(data.status === 'Approved' || data.status === 'Changes Requested') {
                    this.isFinalized = true;
                }
            })
            .catch(err => {
                console.error(err);
                this.error = 'Invalid Link or Record not found.';
            });
    }

    get statusBadgeClass() {
        if(this.fileData.status === 'Approved') return 'slds-badge slds-theme_success';
        if(this.fileData.status === 'Changes Requested') return 'slds-badge slds-theme_error';
        return 'slds-badge';
    }

    toggleComments() { 
        this.showCommentBox = !this.showCommentBox; 
    }

    handleCommentChange(event) { 
        this.comments = event.target.value; 
    }

    // --- STEP 1: INITIAL CLICK HANDLERS ---

    // User clicks "Approve Design"
    handleApproveClick() { 
        // Requirement: If comment box is open, close it
        if(this.showCommentBox) {
            this.showCommentBox = false;
            // Optional: clear comments if they changed their mind
            // this.comments = ''; 
        }

        // Set pending action
        this.pendingStatus = 'Approved';
        this.confirmationMessage = 'Are you sure you want to approve this design?';
        this.showConfirmationModal = true;
    }

    // User clicks "Submit Changes" inside the comment box
    handleSubmitChangesClick() {
        if(!this.comments) {
            const inputField = this.template.querySelector('lightning-textarea');
            inputField.setCustomValidity('Comments required for change requests.');
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
        // Close confirmation modal
        this.showConfirmationModal = false;
        // Proceed to API call
        if(this.pendingStatus) {
            this.submit(this.pendingStatus);
        }
    }

    // --- STEP 3: API SUBMISSION ---

    submit(status) {
        this.error = null;
        this.isLoading = true; 

        submitDecision({ token: this.token, status: status, comments: this.comments })
            .then(() => {
                this.isLoading = false;
                this.isFinalized = true;
                this.fileData = { ...this.fileData, status: status, comments: this.comments };
                
                // Prepare Success Message based on action
                if(status === 'Approved') {
                    this.successMessage = 'The design has been successfully approved. We will proceed to the next steps.';
                } else {
                    this.successMessage = 'Your change request has been submitted successfully. Our team will review your notes.';
                }

                // Show Success Modal
                this.showSuccessModal = true;
            })
            .catch(err => {
                console.error('Submit Error:', err);
                this.error = 'Error submitting response. Please try again.';
                this.isLoading = false; 
            });
    }

    // --- STEP 4: SUCCESS MODAL CLOSE (REDIRECT) ---

    handleSuccessClose() {
        // Redirect to Site Label URL
        window.location.href = ARELIA_SITE_URL;
    }
}