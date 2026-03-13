import { LightningElement, wire, track, api } from "lwc";
import getFilesByOpportunityId from "@salesforce/apex/VendorEmailController.getFilesByOpportunityId";
import getVendorCategories from "@salesforce/apex/VendorEmailController.getVendorCategories";
import getVendorsByCategory from "@salesforce/apex/VendorEmailController.getVendorsByCategory";
import getSpecificationsByOpportunityAndCategory from "@salesforce/apex/VendorEmailController.getSpecificationsByOpportunityAndCategory";
import getAbscondedVendorTasks from "@salesforce/apex/VendorEmailController.getAbscondedVendorTasks";
import sendEmailToVendors from "@salesforce/apex/VendorEmailController.sendEmailToVendors";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";

export default class SendVendorEmailWizard extends LightningElement {
  @api recordId;

  @track isLoading = false;
  @track isStepOne = true;
  @track isStepTwo = false;
  @track isStepThree = false;

  @track tenderType = "New";

  // Files
  @track files = [];
  @track selectedFileIds = [];
  @track showPreview = false;
  @track previewUrl = "";
  @track previewFileName = "";
  @track isImagePreview = false;
  @track currentFileId;
  @track fileColumns = [
    { label: "File Name", fieldName: "Title", type: "text" },
    { label: "Type", fieldName: "FileType", type: "text" },
    {
      type: "action",
      typeAttributes: {
        rowActions: [
          { label: "Preview", name: "preview", iconName: "utility:preview" }
        ]
      }
    }
  ];

  // Vendors & Specs
  @track categoryOptions = [];
  @track selectedCategory = "";
  @track selectedVendorIds = [];

  @track specifications = [];
  @track showSpecificationTable = false;

  @track vendorColumns = [
    { label: "Name", fieldName: "Name", type: "text" },
    { label: "Email", fieldName: "Email__c", type: "email" },
    { label: "Category", fieldName: "Vendor_Category__c", type: "text" },
    {
      label: "Efficiency Rating",
      fieldName: "Average_Efficiency__c",
      type: "number"
    }
  ];

  // Absconded
  @track isLoadingAbscondedTasks = false;
  @track abscondedTasks = [];
  @track abscondedTaskColumns = [
    { label: "Task", fieldName: "taskSubject", type: "text" },
    { label: "Status", fieldName: "taskStatus", type: "text" }
  ];
  @track overallAssignmentCompletionPercentage;
  @track overallAssignmentStartDate;
  @track overallAssignmentEndDate;

  get tenderTypeOptions() {
    return [
      { label: "New Tendor Invitation", value: "New" },
      {
        label: "Backup Tendor Invitation (for Absconded Vendor)",
        value: "Backup"
      }
    ];
  }

  get isBackupFlow() {
    return this.tenderType === "Backup";
  }
  get isSendDisabled() {
    return !this.selectedVendorIds || this.selectedVendorIds.length === 0;
  }

  @wire(getFilesByOpportunityId, { opportunityId: "$recordId" })
  wiredFiles({ data, error }) {
    if (data) {
      this.files = data.map((file) => ({
        ...file,
        Id: file.Id,
        ContentDocumentId: file.ContentDocumentId
      }));
    } else if (error) console.error(error);
  }

  @wire(getVendorsByCategory, { category: "$selectedCategory" })
  vendors;

  connectedCallback() {
    this.loadVendorCategories();
  }

  loadVendorCategories() {
    getVendorCategories()
      .then((result) => {
        this.categoryOptions = result.map((c) => ({ label: c, value: c }));
      })
      .catch(() =>
        this.showToast("Error", "Failed to load vendor categories", "error")
      );
  }

  handleTenderTypeChange(event) {
    this.tenderType = event.detail.value;
  }

  async handleCategoryChange(event) {
    this.selectedCategory = event.detail.value;
    this.selectedVendorIds = [];
    this.specifications = [];
    this.abscondedTasks = [];
    this.showSpecificationTable = false;
    this.overallAssignmentCompletionPercentage = undefined;
    this.overallAssignmentStartDate = undefined;
    this.overallAssignmentEndDate = undefined;

    if (this.selectedCategory && this.recordId) {
      this.isLoading = true;
      try {
        if (this.tenderType === "New") {
          const result = await getSpecificationsByOpportunityAndCategory({
            opportunityId: this.recordId,
            category: this.selectedCategory
          });
          this.specifications = result || [];
          this.showSpecificationTable = this.specifications.length > 0;
        }

        if (this.tenderType === "Backup") {
          this.isLoadingAbscondedTasks = true;
          const result = await getAbscondedVendorTasks({
            opportunityId: this.recordId,
            category: this.selectedCategory
          });

          if (result) {
            this.abscondedTasks = result.tasks || [];
            this.overallAssignmentCompletionPercentage =
              result.overallCompletion;
            this.overallAssignmentStartDate = result.overallAssignmentStartDate;
            this.overallAssignmentEndDate = result.overallAssignmentEndDate;
          } else {
            this.abscondedTasks = [];
          }
          this.isLoadingAbscondedTasks = false;
        }
      } catch (error) {
        console.error(error);
        this.showToast(
          "Error",
          "Failed to load data. Please check configuration.",
          "error"
        );
      } finally {
        this.isLoading = false;
      }
    }
  }

  handleFileSelection(event) {
    this.selectedFileIds = event.detail.selectedRows.map((row) => row.Id);
  }
  handleVendorSelection(event) {
    this.selectedVendorIds = event.detail.selectedRows.map((row) => row.Id);
  }

  handleRowAction(event) {
    if (event.detail.action.name === "preview")
      this.showFilePreview(event.detail.row);
  }

  handleSendEmail() {
    if (!this.selectedVendorIds || this.selectedVendorIds.length === 0) {
      this.showToast("Error", "Please select at least one vendor.", "error");
      return;
    }

    this.isLoading = true;

    sendEmailToVendors({
      opportunityId: this.recordId,
      fileIds: this.selectedFileIds,
      vendorIds: this.selectedVendorIds,
      category: this.selectedCategory,
      tenderType: this.tenderType
    })
      .then(() => {
        this.showToast("Success", "Emails sent successfully!", "success");
        this.closeQuickAction();
      })
      .catch((error) => {
        this.showToast(
          "Error",
          error.body?.message || "Error sending emails",
          "error"
        );
      })
      .finally(() => (this.isLoading = false));
  }

  handleDownloadFile() {
    if (this.currentFileId)
      window.open(
        `/sfc/servlet.shepherd/document/download/${this.currentFileId}`,
        "_blank"
      );
  }

  goToStepOne() {
    this.isStepOne = true;
    this.isStepTwo = false;
    this.isStepThree = false;
  }
  goToStepTwo() {
    this.isStepOne = false;
    this.isStepTwo = true;
    this.isStepThree = false;
  }
  goToStepThree() {
    this.isStepOne = false;
    this.isStepTwo = false;
    this.isStepThree = true;
  }

  showFilePreview(file) {
    this.isImagePreview = [
      "JPG",
      "JPEG",
      "PNG",
      "GIF",
      "BMP",
      "WEBP",
      "SVG"
    ].includes(file.FileType?.toUpperCase());
    this.currentFileId = file.ContentDocumentId;
    if (this.isImagePreview)
      this.previewUrl = `/sfc/servlet.shepherd/document/download/${file.ContentDocumentId}`;
    this.previewFileName = file.Title;
    this.showPreview = true;
  }
  closePreview() {
    this.showPreview = false;
    this.previewUrl = "";
    this.previewFileName = "";
  }
  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
  closeQuickAction() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}