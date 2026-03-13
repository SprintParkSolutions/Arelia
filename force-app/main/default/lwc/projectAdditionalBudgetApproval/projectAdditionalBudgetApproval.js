import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import HOME_URL from "@salesforce/label/c.Arelia_Site_Label";

import getProject from "@salesforce/apex/ProjectAdditionalBudgetController.getProject";
import approveRequest from "@salesforce/apex/ProjectAdditionalBudgetController.approveRequest";
import rejectRequest from "@salesforce/apex/ProjectAdditionalBudgetController.rejectRequest";

export default class ProjectAdditionalBudgetApproval extends LightningElement {
  projectId;
  project;
  error;

  isBusy = false;
  hasResponded = false; // ✅ one-time response lock

  showHistory = false;

  showRejectBox = false;
  rejectionReason = "";

  get historyBtnLabel() {
    return this.showHistory ? "Hide History" : "View History";
  }

  get disableActions() {
    return this.isBusy || this.hasResponded;
  }

  @wire(CurrentPageReference)
  setCurrentPageRef(pageRef) {
    const st = pageRef?.state || {};
    this.projectId =
      st.id || st.c__id || st.recordId || st.c__recordId || this.projectId;

    if (!this.projectId) {
      this.project = null;
      this.error =
        "Missing Project Id in URL. Use: /s/additional-budget-approval?id=PROJECT_ID";
      return;
    }
    this.loadProject();
  }

  toggleHistory() {
    this.showHistory = !this.showHistory;
  }

  loadProject() {
    this.isBusy = true;
    this.error = null;

    getProject({ projectId: this.projectId })
      .then((res) => {
        this.project = res;
      })
      .catch((e) => {
        this.project = null;
        this.error = this.normalizeError(e);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  // -------------------
  // Approve (single click)
  // -------------------
  approve() {
    if (this.disableActions) return;

    this.isBusy = true;
    this.hasResponded = true; // ✅ disable buttons immediately
    this.error = null;

    approveRequest({ projectId: this.projectId })
      .then(() => {
        this.toast("Approved", "Approved successfully. Notifications sent.", "success");
        this.navigateHome();
      })
      .catch((e) => {
        // allow retry only if server failed
        this.hasResponded = false;
        this.error = this.normalizeError(e);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  // -------------------
  // Reject flow
  // -------------------
  openReject() {
    if (this.disableActions) return;
    this.rejectionReason = "";
    this.showRejectBox = true;
  }

  cancelReject() {
    if (this.disableActions) return;
    this.showRejectBox = false;
    this.rejectionReason = "";
  }

  handleRejectionReasonChange(event) {
    this.rejectionReason = event.target.value;
  }

  confirmReject() {
    if (this.disableActions) return;

    const reason = (this.rejectionReason || "").trim();
    if (!reason) {
      this.toast("Missing Reason", "Please enter the rejection reason.", "error");
      return;
    }

    this.isBusy = true;
    this.hasResponded = true; // ✅ disable buttons immediately
    this.error = null;

    rejectRequest({ projectId: this.projectId, rejectionReason: reason })
      .then(() => {
        this.toast("Rejected", "Rejected successfully. Notification sent.", "success");
        this.navigateHome();
      })
      .catch((e) => {
        // allow retry only if server failed
        this.hasResponded = false;
        this.error = this.normalizeError(e);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  // -------------------
  // Navigate Home (Label)
  // -------------------
  navigateHome() {
    const url = HOME_URL;
    window.location.assign(url ? url : "/s/");
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  normalizeError(e) {
    if (!e) return "Unknown error";
    if (Array.isArray(e.body)) return e.body.map((x) => x.message).join(", ");
    if (e.body?.message) return e.body.message;
    return e.message || "Unknown error";
  }
}