import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CloseActionScreenEvent } from 'lightning/actions';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRelatedImages from '@salesforce/apex/ImageApprovalController.getRelatedImages';
import sendDesignBundle from '@salesforce/apex/ImageApprovalController.sendDesignBundle';

// Columns for the history table
const COLUMNS = [
    { label: 'Package Name', fieldName: 'title', type: 'text', wrapText: true },
    { label: 'Sent Date', fieldName: 'createdDate', type: 'date', typeAttributes: { year: "numeric", month: "short", day: "2-digit" }},
    { label: 'Status', fieldName: 'status', type: 'text' }, // You can use cellAttributes class if needed
    { label: 'Client Comments', fieldName: 'clientComments', type: 'text', wrapText: true },
    { label: 'Manager Approved', fieldName: 'managerApproved', type: 'boolean', cellAttributes: { alignment: 'center' } },
    { label: 'Manager Comments', fieldName: 'managerComments', type: 'text', wrapText: true }
];

export default class DesignSubmission extends LightningElement {
    @api recordId;
    @track files = [];
    @track uploadedFiles = [];
    @track budget;
    @track isLoading = false;
    wiredFilesResult;
    columns = COLUMNS;

    get acceptedFormats() { return ['.pdf', '.png', '.jpg', '.zip', '.dwg']; }
    get hasFiles() { return this.files && this.files.length > 0; }
    get hasUploadedFiles() { return this.uploadedFiles && this.uploadedFiles.length > 0; }

    @wire(getRelatedImages, { recordId: '$recordId' })
    wiredFiles(result) {
        this.wiredFilesResult = result;
        if (result.data) {
            this.files = result.data;
        }
    }

    handleUploadFinished(event) {
        const newFiles = event.detail.files;
        this.uploadedFiles = [...this.uploadedFiles, ...newFiles];
        this.showToast('Success', `${newFiles.length} file(s) uploaded`, 'success');
    }

    handleBudgetChange(event) {
        this.budget = event.target.value;
    }

   
    async handleDeleteFile(event) {
        const fileId = event.target.dataset.id;
        this.isLoading = true;
        try {
            await deleteRecord(fileId);
            this.uploadedFiles = this.uploadedFiles.filter(file => file.documentId !== fileId);
            this.showToast('Success', 'File removed successfully', 'success');
        } catch (error) {
            // FIX: Log the error so the variable is "used"
            console.error('Error deleting file:', error);
            this.showToast('Error', 'Error deleting file', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    async handleSendClick() {
        if (!this.budget) {
            this.showToast('Error', 'Please enter a budget amount.', 'error');
            return;
        }
        
        // Ensure at least one file is present
        if (this.uploadedFiles.length === 0) {
            this.showToast('Error', 'Please upload at least one design file.', 'error');
            return;
        }

        this.isLoading = true;
        const fileIds = this.uploadedFiles.map(f => f.documentId);

        try {
            await sendDesignBundle({
                recordId: this.recordId,
                fileIds: fileIds,
                budget: this.budget
            });
            
            this.showToast('Success', 'Design Package Submitted!', 'success');
            
            // Clear UI
            this.uploadedFiles = [];
            this.budget = null;
            
            this.dispatchEvent(new CloseActionScreenEvent());
            refreshApex(this.wiredFilesResult);
            
        } catch (error) {
            this.showToast('Error', error.body ? error.body.message : 'Unknown error', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}