import { notFound } from "next/navigation";
import { DASHBOARD_SLUGS, DASHBOARD_UPLOAD_SLUG } from "../../../config/routes";
import type { DashboardSubTab } from "../../../types/view";
import { DashboardPage } from "../../../views/DashboardPage";

export const dynamicParams = false;

export function generateStaticParams() {
  return [...Object.values(DASHBOARD_SLUGS), DASHBOARD_UPLOAD_SLUG].map((aba) => ({ aba }));
}

export default async function Page({ params }: { params: Promise<{ aba: string }> }) {
  const { aba } = await params;
  if (aba === DASHBOARD_UPLOAD_SLUG) return <DashboardPage subTab="indicadores" showUpload />;

  const subTab = (Object.keys(DASHBOARD_SLUGS) as DashboardSubTab[]).find((k) => DASHBOARD_SLUGS[k] === aba);
  if (!subTab) notFound();
  return <DashboardPage subTab={subTab} showUpload={false} />;
}
