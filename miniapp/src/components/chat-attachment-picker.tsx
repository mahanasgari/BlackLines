/** Shared attachment draft types for chat composer + message rendering. */

export type ChatAttachmentDraft =
  | {
      type: "subscription";
      subscription_id: number;
      email: string;
      label: string | null;
      plan_title: string;
    }
  | {
      type: "link";
      subscription_id: number;
      link_index: number;
      email: string;
      label: string | null;
      plan_title: string;
      link_preview: string;
    }
  | {
      type: "order";
      order_id: number;
      plan_title: string;
      kind: "vpn_purchase" | "wallet_topup";
      kind_label: string;
      amount_label: string;
      status_label: string;
      has_receipt: boolean;
    };
