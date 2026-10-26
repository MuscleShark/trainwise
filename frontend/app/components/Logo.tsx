// The stacked IRON / SAGE logo (brand/logo.svg), in its dark version when the page is
// dark. A plain <picture> because next/image can't switch sources by color scheme.
export default function Logo({ height, className }: { height: number; className?: string }) {
  const width = Math.round((height * 400) / 507);
  return (
    <picture>
      <source srcSet="/brand/logo-dark.svg" media="(prefers-color-scheme: dark)" />
      <img src="/brand/logo.svg" alt="IronSage" width={width} height={height} className={className} />
    </picture>
  );
}
