import * as fcl from "@onflow/fcl";
import { useEffect, useState } from "react";
import Head from "next/head";
import Navbar from "../components/Navbar";
import { useAuth } from "../contexts/AuthContext";
import { checkIsAvailable, getRentCost } from "../flow/scripts"
import styles from "../styles/Purchase.module.css";
import registerDomain, { initializeAccount } from "../flow/transactions";

// Maintain a constant for seconds per year
const SECONDS_PER_YEAR = 365 * 24 * 60 * 60;

export default function Purchase() {
    // Use the AuthCOntext to check whether the connected user is initialized or not
    const { isInitialized, checkInit } = useAuth();
    // Stae variable to keep track of the domain name user  wants
    const [name, setName] = useState("");
    //Stae variable to keep track of how many years
    // the user wants to rent the domain for
    const [years, setYears] = useState(1);
    // State variable to keep track of the cost of the purchase
    const [cost, setCost] = useState(0.0);
    // Loading state
    const [loading, setLoading] = useState(false);

    // Function to initialize a user's account if not already initialized
    async function initialize() {
        try {
            const txId = await initializeAccount();
            
            // This method awaits for the the transaction to be sealed (mined)
            await fcl.tx(txId).onceSealed();
            // Recheck account initialization after the transaction succeeds
            await checkInit();
        } catch (error) {
            console.error(error);
        }
    }

    // Function which calls the register domain
    async function purchase() {
        try {
            setLoading(true);
            const isAvailable = await checkIsAvailable(name);
            if (!isAvailable) throw new Error("Domain is not available");
            
            if (years <=0 ) throw new Error("You must rent for at least 1 year");
            const duration = (years * SECONDS_PER_YEAR).toFixed(1).toString();
            const txId = await registerDomain(name, duration);
            await fcl.tx(txId).onceSealed();

        } catch (error) {
            console.error(error);
        } finally {
            setLoading(false);
        }
    }

    
  // Function which calculates cost of purchase as user 
  // updates the name and duration
  async function getCost() {
    if (name.length > 0 && years > 0) {
      const duration = (years * SECONDS_PER_YEAR).toFixed(1).toString();
      const c = await getRentCost(name, duration);
      setCost(c);
    }
  }

  // Call getCost() every time `name` and `years` changes
  useEffect(() => {
    getCost();
  }, [name, years]);

  return (
    <div className={styles.container}>
      <Head>
        <title>Flow Name Service - Purchase</title>
        <meta name="description" content="Flow Name Service" />
        <link rel="icon" href="/favicon.ico" />
      </Head>

      <Navbar />

      {!isInitialized ? (
        <>
          <p>Your account has not been initialized yet</p>
          <button onClick={initialize}>Initialize Account</button>
        </>
      ) : (
        <main className={styles.main}>
          <div className={styles.inputGroup}>
            <span>Name: </span>
            <input
              type="text"
              value={name}
              placeholder="learnweb3"
              onChange={(e) => setName(e.target.value)}
            />
            <span>.fns</span>
          </div>

          <div className={styles.inputGroup}>
            <span>Duration: </span>
            <input
              type="number"
              placeholder="1"
              value={years}
              onChange={(e) => setYears(e.target.value)}
            />
            <span>years</span>
          </div>
          <button onClick={purchase}>Purchase</button>
          <p>Cost: {cost} FLOW</p>
          <p>{loading ? "Loading..." : null}</p>
        </main>
      )}
    </div>
  );
}