import { makeStyles } from '@material-ui/core';

const useStyles = makeStyles({
  svg: {
    width: 28,
    height: 28,
    flex: '0 0 28px',
  },
});

export const LogoIcon = () => {
  const classes = useStyles();

  return (
    <svg
      className={classes.svg}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 32 32"
      role="img"
      aria-label="Portal"
    >
      <rect width="32" height="32" rx="7" fill="#102a2d" />
      <path
        d="M9 22V10h8.4c3.3 0 5.6 2.2 5.6 5.2s-2.3 5.2-5.6 5.2h-4.5V22H9Zm3.9-4.7h4.2c1.2 0 2-.8 2-2.1s-.8-2.1-2-2.1h-4.2v4.2Z"
        fill="#7df3e1"
      />
      <path d="M8 24h16v2H8v-2Z" fill="#ffffff" opacity="0.82" />
    </svg>
  );
};
